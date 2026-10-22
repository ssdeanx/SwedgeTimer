-- tests/neutral_actions_state.lua: the per-class NEUTRAL action sets.
--
-- WHAT THIS SUITE PINS (the contract the orchestrator fixed):
--
--   ST.<CLASS>.practice_neutral_actions
--     = { heal = true, shield = true }                   -- the same set everywhere
--     = { ERA = { heal = true }, TBC = { heal = true } } -- per family
--
--   The NEUTRAL action set: the action keys that are legitimate but NOT rotation
--   actions (a potion, a trinket, a heal, a movement ability). The engine treats
--   a press of one of these keys as NEUTRAL: no attempt, no points, no streak
--   change, and NOT a mis-pick. A key that is neither a rotation action nor
--   neutral stays a MIS-PICK (F), so the set must be a deliberate, CLOSED list -
--   never "everything except the rotation".
--
-- THE PANEL ABILITY VOCABULARY (what "the class's own practice-panel ability
-- keys" means here, and the vocabulary every key is classified against):
--
--   panel(class, slice) = the rotation slice the panel grades against
--                        + the class's own guide slot keys (the panel's action row)
--                        + the class's own PRACTICE-PANEL ability list (the common
--                          abilities the panel offers: ST.<CLASS>.practice_common_actions
--                          - a heal, a shield, food, a potion, a movement spell)
--                        + the shared sim's grid keys (the paladin's panel grid:
--                          practice.lua's ABILITY_ORDER - the twist sim's ability
--                          list, the only class that runs the shared sim session)
--                        + the class's own DRILL grid (the drill's own cast keys -
--                          the panel's drill row: the hunter's PRACTICE_SHOT_ORDER,
--                          the druid's powershift cast). A drill's own truth is
--                          never a neutral action, and where the rotation never
--                          asks for it the key is an intentional mis-pick.
--
--   The rotation slice is the class's OWN published slice for the running client:
--   ST.<CLASS>.practice_rotation_for(...) - the paladin's takes an ORDER id (the
--   twist / wrath / sod_* orders), the other three take a FAMILY token.
--
--   The guide slot keys are the CANONICAL ones (the shipped action row offers
--   every action under its canonical key - the paladin's "consecration" slot is
--   the rotation's "cons"), so the vocabulary here is the vocabulary the player
--   sees: one key per spell, never two spellings of one spell.
--
--   The practice-panel ability list is family-gated per entry (the `families` field):
--   an entry with no gate is offered on every family, an entry with a gate is offered
--   only on the families it names. The gate is the CLIENT family token - the same
--   token the engine's family-scoped neutral publish reads (st.family) - so the
--   panel's offer and the neutral set can never disagree.
--
-- THE CLASSIFICATION (every panel key gets exactly one label):
--
--   ROTATION  the key (normalised through the class's own alias table) is an
--             action the rotation can ask for on this slice. The rotation grades
--             it.
--   NEUTRAL   the key is in the class's published neutral set for this family.
--             Legitimate, but the rotation never asks for it.
--   MISPICK   the key is neither. An INTENTIONAL mis-pick: the rotation would
--             ask for it on another slice, or the client cannot cast it at all.
--             The suite holds the explicit list, so a key nobody classified
--             fails the suite - the next ability someone adds cannot silently
--             become a free press.
--
-- THE GRADING-INTEGRITY PIN (the mutant this suite must kill):
--   no published neutral key may be a rotation action on the slice it is
--   published for. The engine grades the EXPECTED action first, so a rotation
--   press still hits - but a rotation action published as neutral would make a
--   WRONG rotation press free. A class that publishes a rotation action as
--   neutral fails here.
--
-- The class suites own the same pins per class (tests/warrior_state.lua,
-- tests/rogue_state.lua, tests/shaman_state.lua); the paladin's pin lives HERE,
-- because tests/paladin_state.lua belongs to another lane.
--
-- Run from the repo root: lua5.1 tests/neutral_actions_state.lua
local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL  " .. label)
    end
end

--=========================================================================================
-- The sandbox builder
--
-- One throwaway client profile per slice: a fresh environment (a metatable over
-- _G, so an absent global is shadowed with nil rather than removed), the real
-- compat.lua + utils.lua + guard.lua + nextaction.lua + nextaction_ui.lua loaded
-- into it, then practice.lua (the shared engine - the class contract's reader)
-- and the class module on top. The client family is the sandbox's WOW_PROJECT_ID
-- (compat.lua's family detection), so compat's st.family IS the slice's family
-- and the engine's own reader resolves the family-scoped publish for it.
--=========================================================================================
local function make_frame(name)
    local f = { name = name, shown = false }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetFrameStrata() end
    function f:SetClampedToScreen() end
    function f:RegisterForDrag() end
    function f:SetScript(event, fn)
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(a) f.alpha = a end
    function f:SetScale(s) f.scale = s end
    function f:GetScale() return f.scale or 1 end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:GetFrameLevel() return 5 end
    function f:SetFrameLevel() end
    function f:GetName() return f.name end
    function f:GetCenter() return 50, 60 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:CreateTexture() return make_frame("tex") end
    function f:CreateFontString() return make_frame("fs") end
    function f:SetBackdrop() end
    function f:SetBackdropBorderColor() end
    function f:SetCooldown() end
    function f:SetReverse() end
    function f:SetHideCountdownNumbers() end
    function f:SetAllPoints() end
    return f
end

-- compat.lua's family tokens and the client project id that answers each one.
-- CATA (the 4.4.3 Classic Cataclysm client, interface 40402) and MISTS (the 5.5.0
-- Classic Mists client, interface 50500) are in the tree (SwedgeTimer_Cata.toc and
-- SwedgeTimer_Mists.toc) and compat.lua detects them by the same project id.
local FAMILY_PROJECT = { ERA = 2, TBC = 5, WRATH = 11, CATA = 14, MISTS = 19, FOREVER = 18, RETAIL = 1 }

local function build(opts)
    local family = opts.family or "ERA"
    local sb = { clock = 0, family = family }
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = FAMILY_PROJECT[family] or 2
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 20506 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...) return make_frame(select(2, ...)) end
    env.GetSpellInfo = function(spell)
        if type(spell) == "number" then
            return "Spell " .. tostring(spell), nil, "icon_" .. tostring(spell), 0, 0, 0, spell
        end
        -- The client's own spell NAMES (the SoD build answers the Mangle and the
        -- Savage Roar - the druid's own SoD rune probe asks for them by name).
        local named = (opts.named_spells or {})[spell]
        if named then
            return named, nil, "icon_named", 0, 0, 0, 0
        end
        return nil
    end
    -- The Season-of-Discovery rune probes (the build, never the spell table): the
    -- hunter's own Chimera Shot rune (409433) and the druid's own Mangle id
    -- (33983). The sandbox states the BUILD; the class's own probe decides.
    env.IsSpellKnown = function(spell)
        if opts.sod and (spell == 409433 or spell == 33983) then
            return true
        end
        return false
    end
    env.GetSpellCooldown = function() return 0, 0, 0, 0 end
    env.GetSpellBaseCooldown = function() return 0 end
    env.UnitPower = function() return 100 end
    env.UnitPowerMax = function() return 100 end
    env.UnitExists = function() return false end
    env.UnitCreatureType = function() return nil end
    env.UnitAura = function() return nil end
    env.InCombatLockdown = function() return false end
    env.GetShapeshiftForm = function() return nil end
    env.IsCurrentSpell = function() return false end
    env.GetSpellPowerCost = function() return nil end
    env.UnitHealth = function() return 100 end
    env.UnitHealthMax = function() return 100 end
    env.IsSpellUsable = function() return true end

    local ST = {
        PALADIN = {}, WARRIOR = {}, HUNTER = {}, ROGUE = {}, SHAMAN = {}, DRUID = {},
        player_class = "WARRIOR",
        interfaces_are_initialised = true,
        in_combat = false,
        db = { profile = { enabled = true } },
    }
    local class_db = {
        nextaction_enabled = true, nextaction_locked = true,
        nextaction_visibility_key = "always", nextaction_x = 0, nextaction_y = -180,
        nextaction_icon_size = 45, nextaction_show_rotation_text = true,
        nextaction_show_label = true, nextaction_show_fillers = true,
        nextaction_show_judgement = true, nextaction_hold_enabled = true,
        nextaction_reaction_time_ms = 100, nextaction_cs_max_delay_ms = 1700,
        nextaction_filler_mana_consecration = 35, nextaction_filler_mana_exorcism = 30,
    }
    function ST.get_class_table() return class_db end

    local LCG = {}
    function LCG.PixelGlow_Start() end
    function LCG.PixelGlow_Stop() end
    local LSM = {}
    function LSM.Fetch() return nil end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        end
        return nil
    end

    local st = {}
    local modules = {
        "compat.lua", "utils.lua", "guard.lua", "nextaction.lua", "nextaction_ui.lua",
        "practice.lua", opts.module,
    }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            error("load " .. modules[i] .. ": " .. tostring(err))
        end
        -- Operator order 2026-10-21: a wrapped class file registers its body as a
        -- loader; the sandbox activates it exactly as main.lua does at init.
        local class = modules[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end
    -- The Season-of-Discovery latch (the SoD build runs on the ERA client; the
    -- latch is the rune observation, so a sandbox can state it).
    if opts.sod then
        ST.weave_mw_observed = true
    end
    sb.env, sb.st, sb.ST = env, st, ST
    -- The class's own BUILD preparation (the SoD swap and the neutral publish's
    -- build pick): the class decides, never the suite.
    if opts.prepare then
        opts.prepare(sb)
    end
    return sb
end

--=========================================================================================
-- The expectations
--
-- Per class, per slice: the NEUTRAL set the class publishes for that family and
-- the INTENTIONAL MIS-PICK list (the panel keys that are neither a rotation
-- action on that slice nor neutral). The mis-pick list is the closed list: a
-- panel key that is in neither the rotation slice, the neutral set nor this list
-- fails the suite.
--=========================================================================================
local CLASSES = {
    PALADIN = {
        module = "classes/paladin.lua",
        -- The paladin's slice is its ORDER (its practice_rotation_for takes an
        -- order id), and the order's own family gate reads compat's st.family -
        -- so the twist order is walked on each family it serves.
        slices = {
            {
                id = "twist", family = "ERA",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "consec", "cons", "cs", "exo", "hor", "hs",
                    "how_wrath", "sob" },
            },
            {
                id = "twist", family = "TBC",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "hor", "how", "how_wrath", "hs" },
            },
            {
                id = "twist", family = "FOREVER",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "cs", "hor", "how_wrath", "hs", "sob" },
            },
            {
                id = "wrath", family = "WRATH",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "hs", "how", "sob", "soc", "twist" },
            },
            {
                id = "sod", family = "ERA",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "hor", "how_wrath", "hs", "sob", "soc", "twist" },
            },
            {
                id = "sod_stack", family = "ERA",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "hor", "how", "how_wrath", "hs", "sob", "soc", "twist" },
            },
            {
                id = "sod_shock", family = "ERA",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "consec", "cons", "hor", "how", "how_wrath", "judge", "sob",
                    "soc", "twist" },
            },
            {
                id = "sod_wrath", family = "ERA",
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "hpot", "holy_light", "lay_on_hands", "sotc", "stop" },
                mispick = { "am", "hor", "how", "how_wrath", "hs", "sob", "soc", "twist" },
            },
            -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients): the
            -- paladin's publish is FAMILY-SCOPED, so those two clients answer
            -- their own bucket - and the bucket carries NO `sotc` (the Seal of
            -- the Crusader was removed in 4.0, so a `sotc` button there is a
            -- dead button). The twist order names no row for those clients
            -- (every row of the order is family-gated), so the rotation slice is
            -- empty there and every published common ability is a legitimate,
            -- ungraded press. The `sotc` key (the shared sim's grid) is therefore
            -- an intentional mis-pick on those clients.
            {
                id = "twist", family = "CATA", live = true,
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "holy_light", "hpot", "lay_on_hands", "stop" },
                mispick = { "am", "consec", "cons", "cs", "exo", "hor", "how", "how_wrath",
                    "hs", "judge", "sob", "soc", "sotc", "twist" },
            },
            {
                id = "twist", family = "MISTS", live = true,
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "holy_light", "hpot", "lay_on_hands", "stop" },
                mispick = { "am", "consec", "cons", "cs", "exo", "hor", "how", "how_wrath",
                    "hs", "judge", "sob", "soc", "sotc", "twist" },
            },
            -- THE RETAIL CLIENT (the mainline client): the same shape as the Cata
            -- and the Mists clients - the paladin publishes no rotation for it
            -- (every row of the twist order is family-gated) and its own bucket
            -- carries the ten legitimate presses (no `sotc` there either).
            {
                id = "twist", family = "RETAIL", live = true,
                neutral = { "abacus", "aw", "bop", "divine_shield", "flash_of_light",
                    "food", "holy_light", "hpot", "lay_on_hands", "stop" },
                mispick = { "am", "consec", "cons", "cs", "exo", "hor", "how", "how_wrath",
                    "hs", "judge", "sob", "soc", "sotc", "twist" },
            },
        },
    },
    WARRIOR = {
        module = "classes/warrior.lua",
        slices = {
            { id = "ERA", family = "ERA",
                neutral = { "demoralizing_shout", "flask", "food", "healthstone", "sprint" },
                mispick = {} },
            { id = "SOD", family = "ERA",
                neutral = { "demoralizing_shout", "flask", "food", "healthstone", "sprint" },
                mispick = {} },
            { id = "TBC", family = "TBC",
                neutral = { "demoralizing_shout", "flask", "food", "healthstone", "sprint" },
                mispick = {} },
            { id = "FOREVER", family = "FOREVER",
                neutral = { "cleave", "demoralizing_shout", "flask", "food", "healthstone", "sprint" },
                mispick = {} },
            { id = "WRATH", family = "WRATH",
                neutral = { "battle_shout", "demoralizing_shout", "flask", "food", "healthstone", "sprint" },
                mispick = {} },
            -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients): the
            -- class publishes NO rotation for them and therefore no neutral bucket
            -- either (a bucket is the class's statement about a client it plays) -
            -- so the OFFER GATE offers no common ability there, and the panel
            -- offers the guide vocabulary alone. The one guide slot the rotation
            -- does not name (the Cleave - a row the engine never emits) is the only
            -- intentional mis-pick.
            { id = "CATA", family = "CATA", live = true,
                neutral = {},
                mispick = { "cleave" } },
            { id = "MISTS", family = "MISTS", live = true,
                neutral = {},
                mispick = { "cleave" } },
        },
    },
    ROGUE = {
        module = "classes/rogue.lua",
        slices = {
            { id = "ERA", family = "ERA",
                neutral = { "coldblood", "evasion", "food", "healthstone", "kick", "sprint" },
                mispick = { "rupture" } },
            { id = "SOD", family = "ERA",
                neutral = { "coldblood", "evasion", "food", "healthstone", "kick", "sprint" },
                mispick = { "rupture" } },
            { id = "TBC", family = "TBC",
                neutral = { "evasion", "food", "healthstone", "kick", "sprint" },
                mispick = {} },
            { id = "WRATH", family = "WRATH",
                neutral = { "coldblood", "evasion", "food", "healthstone", "kick", "shiv", "sprint" },
                mispick = {} },
            { id = "FOREVER", family = "FOREVER",
                neutral = { "evasion", "food", "healthstone", "kick", "shiv", "sprint" },
                mispick = {} },
            -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients): the
            -- class publishes NO rotation for them and therefore no neutral bucket
            -- either (a bucket is the class's statement about a client it plays) -
            -- so the OFFER GATE offers no common ability there, and every key of
            -- the class's own (flat) guide vocabulary is an intentional mis-pick.
            { id = "CATA", family = "CATA", live = true,
                neutral = {},
                mispick = { "ar", "bf", "builder", "coldblood", "envenom", "eviscerate",
                    "expose", "rupture", "shiv", "snd", "tea" } },
            { id = "MISTS", family = "MISTS", live = true,
                neutral = {},
                mispick = { "ar", "bf", "builder", "coldblood", "envenom", "eviscerate",
                    "expose", "rupture", "shiv", "snd", "tea" } },
        },
    },
    SHAMAN = {
        module = "classes/shaman.lua",
        slices = {
            { id = "ERA", family = "ERA", neutral = { "chain_heal", "food", "healing_potion",
                "healing_wave", "water_shield" }, mispick = {} },
            { id = "SOD", family = "ERA", sod = true, neutral = { "chain_heal", "food",
                "healing_potion", "healing_wave", "water_shield" }, mispick = {} },
            { id = "TBC", family = "TBC", neutral = { "chain_heal", "food", "healing_potion",
                "healing_wave", "water_shield" }, mispick = {} },
            { id = "WRATH", family = "WRATH", neutral = { "chain_heal", "food", "healing_potion",
                "healing_wave", "water_shield" }, mispick = {} },
            { id = "FOREVER", family = "FOREVER", neutral = { "chain_heal", "food",
                "healing_potion", "healing_wave", "water_shield" }, mispick = {} },
            -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients): the
            -- shaman's publish is FLAT, so it answers every family - the class
            -- publishes no rotation for those two clients (the rotation table
            -- carries no CATA / MISTS row), and the class's own rule leaves its
            -- FULL guide vocabulary standing on a family it carries no row for, so
            -- every key of that vocabulary is an intentional mis-pick there.
            { id = "CATA", family = "CATA", live = true, neutral = { "chain_heal", "food",
                "healing_potion", "healing_wave", "water_shield" },
                mispick = { "bloodlust", "chainlightning", "coe", "earthshock", "fireele",
                    "feralspirit", "firenova", "flameshock", "frostshock", "goa",
                    "lavalash", "lightningshield", "magma", "mana_spring", "moltenblast",
                    "searing", "shamanisticrage", "stormstrike", "strength_of_earth",
                    "twist", "weave", "wftotem" } },
            { id = "MISTS", family = "MISTS", live = true, neutral = { "chain_heal", "food",
                "healing_potion", "healing_wave", "water_shield" },
                mispick = { "bloodlust", "chainlightning", "coe", "earthshock", "fireele",
                    "feralspirit", "firenova", "flameshock", "frostshock", "goa",
                    "lavalash", "lightningshield", "magma", "mana_spring", "moltenblast",
                    "searing", "shamanisticrage", "stormstrike", "strength_of_earth",
                    "twist", "weave", "wftotem" } },
        },
    },
    HUNTER = {
        module = "classes/hunter.lua",
        -- The SoD build's spell data answers the Mangle and the Savage Roar (the
        -- druid's own probe asks for them by name) - the hunter's own probe asks
        -- for the Chimera Shot rune id, which the sandbox answers through
        -- IsSpellKnown.
        prepare = function(sb)
            -- The ONE build decision: the SoD slot swap (which also runs the
            -- neutral publish's build pick - the same decision drives both).
            sb.ST.HUNTER.resolve_guide_icons()
        end,
        slices = {
            -- The ERA token, the ERA-base game: the rotation asks for neither the
            -- Raptor Strike nor the Steady Shot, so both are panel keys the
            -- rotation never grades (the Raptor Strike is neutral, the Steady
            -- Shot is the drill's own cast - an intentional mis-pick).
            { id = "ERA", family = "ERA",
                neutral = { "concussive_shot", "food", "healthstone", "healing_potion",
                    "raptor", "sprint" },
                mispick = { "steady" } },
            -- The SoD build (the ERA token, the SoD game): the rotation DOES ask
            -- for the Raptor Strike (under the key `raptor_strike`), so the
            -- `raptor` key is not published as neutral there - a rotation action
            -- can never be neutral. The SoD rotation carries no Bestial Wrath
            -- row, so that slot is an intentional mis-pick.
            { id = "SOD", family = "ERA", sod = true,
                neutral = { "concussive_shot", "food", "healthstone", "healing_potion",
                    "sprint" },
                mispick = { "bestial_wrath", "raptor", "steady" } },
            -- The TBC client: the rotation asks for neither the Raptor Strike nor
            -- the Aimed Shot, so the Raptor Strike is neutral and the Aimed Shot
            -- (the drill's own cast) is an intentional mis-pick.
            { id = "TBC", family = "TBC",
                neutral = { "concussive_shot", "food", "healthstone", "healing_potion",
                    "raptor", "sprint" },
                mispick = { "aimed" } },
            -- The WotLK client: the guide slots and the rotation rows are the same
            -- keys there (the Raptor Strike is not a WotLK guide slot at all), so
            -- the panel carries no mis-pick.
            { id = "WRATH", family = "WRATH",
                neutral = { "concussive_shot", "food", "healthstone", "healing_potion",
                    "sprint" },
                mispick = {} },
            -- The Forever client: the rotation asks for the Raptor Strike (under
            -- the key `raptor_strike`), so the `raptor` guide slot is an
            -- intentional mis-pick, and so are the drill's own Steady Shot and
            -- Aimed Shot (the client has neither spell).
            { id = "FOREVER", family = "FOREVER",
                neutral = { "concussive_shot", "food", "healthstone", "healing_potion",
                    "sprint" },
                mispick = { "aimed", "raptor", "steady" } },
            -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients): the
            -- class publishes NO rotation for them and therefore no neutral bucket
            -- either (a bucket is the class's statement about a client it plays) -
            -- so the OFFER GATE offers no common ability there, and every guide
            -- slot is an intentional mis-pick. The Mists guide set carries no
            -- Raptor Strike (the client's own spell data has none this tree knows),
            -- so the Cata slice has one more mis-pick than the Mists slice.
            { id = "CATA", family = "CATA", live = true,
                neutral = {},
                mispick = { "aimed", "bestial_wrath", "kill_command", "multi", "raptor",
                    "rapid_fire", "steady" } },
            { id = "MISTS", family = "MISTS", live = true,
                neutral = {},
                mispick = { "aimed", "bestial_wrath", "kill_command", "multi",
                    "rapid_fire", "steady" } },
        },
    },
    DRUID = {
        module = "classes/druid.lua",
        -- The SoD build's spell data answers the Mangle and the Savage Roar (the
        -- class's own SoD rune probe asks for them by name - the id probe comes
        -- first and the sandbox answers the Mangle id too).
        sod_named = { ["Mangle"] = "Mangle", ["Savage Roar"] = "Savage Roar" },
        prepare = function(sb)
            -- The class's own build decision (the SoD rune basis the rotation
            -- family carries): reading the rotation family latches the probe, and
            -- the class's own latch corrects the neutral publish. The suite never
            -- calls the pick itself - the class's wiring is the contract.
            sb.ST.DRUID.practice_rotation_family()
        end,
        slices = {
            -- The ERA token, the ERA-base game: the cat rotation asks for neither
            -- the Rake nor the Bite, so the Rake is neutral and the Bite (the
            -- client has no Ferocious Bite) is an intentional mis-pick - and so
            -- are the bear chain's Maul, the Mangle (2.3+) and the drill's own
            -- shift.
            { id = "ERA", family = "ERA",
                neutral = { "cheetah", "food", "healthstone", "healing_potion",
                    "healing_touch", "rake", "regrowth", "rejuvenation" },
                mispick = { "bite", "maul", "mangle", "shift" } },
            -- The SoD build (the ERA token, the SoD game): the rotation DOES ask
            -- for the Rake (its upkeep S7), so the `rake` key is not published as
            -- neutral there - a rotation action can never be neutral.
            { id = "SOD", family = "ERA", sod = true,
                neutral = { "cheetah", "food", "healthstone", "healing_potion",
                    "healing_touch", "regrowth", "rejuvenation" },
                mispick = { "bite", "claw", "maul", "shift" } },
            -- The TBC client: the cat rotation asks for neither the Rake nor the
            -- Bite, so the Rake is neutral; the Bite IS a rotation row there
            -- (T3), and the Claw is a guide slot the TBC rotation never asks for.
            { id = "TBC", family = "TBC",
                neutral = { "cheetah", "food", "healthstone", "healing_potion",
                    "healing_touch", "rake", "regrowth", "rejuvenation" },
                mispick = { "claw", "maul", "shift" } },
            -- The WotLK client: the Rake IS a rotation row there (the upkeep W7),
            -- so it is deliberately not published.
            { id = "WRATH", family = "WRATH",
                neutral = { "cheetah", "food", "healthstone", "healing_potion",
                    "healing_touch", "regrowth", "rejuvenation" },
                mispick = { "claw", "maul", "shift" } },
            -- The Forever client: the Rake IS a rotation row there (the upkeep
            -- F4) and the Mangle is no spell at all on that client, so neither is
            -- published.
            { id = "FOREVER", family = "FOREVER",
                neutral = { "cheetah", "food", "healthstone", "healing_potion",
                    "healing_touch", "regrowth", "rejuvenation" },
                mispick = { "maul", "mangle", "shift" } },
            -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients): the
            -- class publishes NO rotation for them and therefore no neutral bucket
            -- either (a bucket is the class's statement about a client it plays) -
            -- so the OFFER GATE offers no common ability there, and every guide
            -- slot of the class's own (flat) cat and bear vocabulary is an
            -- intentional mis-pick.
            { id = "CATA", family = "CATA", live = true,
                neutral = {},
                mispick = { "bite", "claw", "maul", "mangle", "rake", "rip", "shift",
                    "shred" } },
            { id = "MISTS", family = "MISTS", live = true,
                neutral = {},
                mispick = { "bite", "claw", "maul", "mangle", "rake", "rip", "shift",
                    "shred" } },
        },
    },
}

--=========================================================================================
-- The helpers
--=========================================================================================
local function keyset(list)
    local out = {}
    for i = 1, #list do
        out[list[i]] = true
    end
    return out
end

-- One sandbox for a class slice: the class's own module, the slice's family, the
-- SoD build flag (with the spell names that build answers) and the class's own
-- build preparation.
local function build_slice(spec, slice)
    return build({
        module = spec.module,
        family = slice.family,
        sod = slice.sod,
        named_spells = (slice.sod and spec.sod_named) or nil,
        prepare = spec.prepare,
    })
end

local function sorted(set)
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    return list
end

local function same_set(a, b)
    for k in pairs(a) do
        if b[k] ~= true then return false, k end
    end
    for k in pairs(b) do
        if a[k] ~= true then return false, k end
    end
    return true
end

-- The rotation slice the panel grades against: the class's OWN published slice.
-- For a family the class DESCRIBES the slice is that family's own table (the
-- paladin's takes an ORDER id, the other three take a FAMILY token). For a family
-- the class does NOT describe - the Cata and the Mists clients, which publish no
-- rotation at all - the panel's own read is the ARGUMENT-FREE call
-- (practice_ui.lua's scenario_action_order calls it with no argument and the class
-- picks the running client's slice), so the slice is read the same way.
local function rotation_slice(M, class_key, slice)
    if class_key == "SHAMAN" or slice.live then
        -- The argument-free call: the panel's own read. The SoD rows ride the ERA
        -- slice, and a family the class does not describe is cut from the running
        -- client's own vocabulary.
        return M.practice_rotation_for()
    end
    return M.practice_rotation_for(slice.id)
end

-- The class's own guide slot keys (the panel's action row).
--
-- THE PANEL OFFERS EVERY ACTION UNDER ITS CANONICAL KEY (the shipped action row
-- canonicalises the guide slots through the class's own alias table: the
-- paladin's "consecration" slot is the rotation's "cons"), so the vocabulary the
-- closed list classifies is the canonical one - the same keys the player sees.
local function guide_slot_keys(M, class_key, slice)
    local out = {}
    if class_key == "PALADIN" or class_key == "ROGUE" then
        local guide = M.guide
        if type(guide) == "table" and type(guide.slots) == "table" then
            for i = 1, #guide.slots do
                local s = guide.slots[i]
                if type(s) == "table" and type(s.key) == "string" then out[s.key] = true end
            end
        end
    elseif class_key == "WARRIOR" then
        local slots = M.practice_rotation_slots(slice.id)
        if type(slots) ~= "table" and slice.live then
            -- A family the class does not describe (the Cata and the Mists
            -- clients) has no per-family set: the running client's own slot set
            -- stands (the class's own argument-free read).
            slots = M.practice_rotation_slots()
        end
        if type(slots) == "table" then
            for i = 1, #slots do
                local s = slots[i]
                if type(s) == "table" and type(s.key) == "string" then out[s.key] = true end
            end
        end
    elseif class_key == "SHAMAN" then
        local fam = M.practice_rotation_family()
        local extra = M.practice_build_family()
        local slots = M.family_guide_slots(fam, extra)
        if type(slots) == "table" and #slots == 0 then
            -- The class's own rule (apply_family_slots): a family the class carries
            -- no row for leaves the class's FULL vocabulary standing - the guide's
            -- slot list keeps every key, so the panel offers them all.
            slots = M.GUIDE_SLOTS
        end
        if type(slots) == "table" then
            for i = 1, #slots do
                local s = slots[i]
                if type(s) == "table" and type(s.key) == "string" then out[s.key] = true end
            end
        end
    elseif class_key == "HUNTER" or class_key == "DRUID" then
        -- Both classes carry one flat guide slot set (the hunter's is picked per
        -- family at load and swapped for the SoD set by the class's own build
        -- decision; the druid's is flat on every family).
        local guide = M.guide
        if type(guide) == "table" and type(guide.slots) == "table" then
            for i = 1, #guide.slots do
                local s = guide.slots[i]
                if type(s) == "table" and type(s.key) == "string" then out[s.key] = true end
            end
        end
    end
    -- The canonical spelling of every key (the class's own alias table; a class
    -- with a single key space has none, and the canonical key is the key itself).
    local aliases = M.practice_action_aliases
    if type(aliases) == "table" then
        local canonical = {}
        for key in pairs(out) do
            canonical[aliases[key] or key] = true
        end
        return canonical
    end
    return out
end

-- The shared sim's grid keys: the paladin is the only class that runs the twist
-- sim session, and the sim's ability list (practice.lua's ABILITY_ORDER) is the
-- grid the paladin panel draws.
local function sim_grid_keys(st, class_key)
    local out = {}
    if class_key == "PALADIN" then
        local pr = st.practice
        if type(pr) ~= "table" or type(pr.ABILITY_ORDER) ~= "table" then return out end
        for i = 1, #pr.ABILITY_ORDER do
            out[pr.ABILITY_ORDER[i]] = true
        end
        return out
    end
    return out
end

-- The class's own DRILL grid: the drill's own cast keys (the panel's drill row,
-- not the rotation scenario's action row). A drill's own truth is never a neutral
-- action, and where the rotation never asks for it the key is an intentional
-- mis-pick.
--   HUNTER  the class's own shot order (steady, multi, aimed - PRACTICE_SHOT_ORDER).
--   DRUID   the powershift drill's cast key ("shift" - practice_ui.lua's
--           DRUID_DRILL_KEY, the key the class's own drill grades).
local function drill_grid_keys(M, class_key)
    local out = {}
    if class_key == "HUNTER" then
        local order = M.PRACTICE_SHOT_ORDER
        if type(order) == "table" then
            for i = 1, #order do
                if type(order[i]) == "string" then out[order[i]] = true end
            end
        end
    elseif class_key == "DRUID" then
        out["shift"] = true
    end
    return out
end

-- The published neutral set for ONE family (the engine's own resolution rule,
-- re-implemented here): a family-scoped publish answers the bucket for that
-- family, a flat publish answers itself, and a family the class published no
-- bucket for answers an empty set (the engine's own reader answers nil there).
local function published_neutral_set(published, family)
    local out = {}
    if type(published) ~= "table" then return out end
    local source = published
    for _, value in pairs(published) do
        if type(value) == "table" then
            -- a family-scoped publish: the running family's own bucket
            source = published[family]
            break
        end
    end
    if type(source) ~= "table" then return out end
    for key, value in pairs(source) do
        if type(key) == "string" and key ~= "" and value == true then
            out[key] = true
        end
    end
    return out
end

-- The class's own PRACTICE-PANEL ability list, filtered to what the class's OWN
-- data offers on this family - the OFFER LIST the rule defines (the
-- orchestrator's ruling, 2026-10-20):
--   * the class's published neutral set for this family carries the key (an
--     ability with no neutral bucket on that family is NOT offered there - it
--     stays available on the families where it IS neutral);
--   * the running family's rotation does not rank the key (a rotation action is
--     graded by the rotation, never an offered common ability);
--   * the entry's own per-ability family gate (the `families` field) names this
--     family, when it carries one.
--
-- This is the rule re-implemented from the class's PUBLISHED data, so the class's
-- own gate must agree with it (the offer pins below).
local function common_action_keys(M, slice, neutral, slice_keys, norm)
    local out = {}
    local list = M.practice_common_actions
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local action = list[i]
        if type(action) == "table" and type(action.key) == "string" and action.key ~= "" then
            local families = action.families
            local offered = true
            if type(families) == "table" then
                offered = false
                for f = 1, #families do
                    if families[f] == slice.family then
                        offered = true
                    end
                end
            end
            if offered and type(neutral) == "table" and neutral[action.key] == true then
                if type(slice_keys) ~= "table" or slice_keys[norm(action.key)] ~= true then
                    out[action.key] = true
                end
            end
        end
    end
    return out
end

-- THE CITED IDS PIN: every published common action names the client's spell (the
-- lookup key the resolution asks for), carries a label for the panel, and cites at
-- least one spell id. An ability whose id nobody can source is not published at all
-- (the class's own rule: never invent an id).
local function check_common_actions(tag, M)
    local list = M.practice_common_actions
    check(type(list) == "table",
        tag .. ": the class publishes ST.<CLASS>.practice_common_actions")
    if type(list) ~= "table" then return end
    check(#list > 0, tag .. ": the practice-panel ability list is not empty")
    for i = 1, #list do
        local action = list[i]
        local key = (type(action) == "table" and type(action.key) == "string") and action.key
            or ("#" .. tostring(i))
        check(type(action) == "table", tag .. ": common action " .. key .. " is a table")
        check(type(action.key) == "string" and action.key ~= "",
            tag .. ": common action " .. key .. " carries a key")
        check(type(action.label) == "string" and action.label ~= "",
            tag .. ": common action " .. key .. " carries a label")
        check(type(action.names) == "table" and #action.names > 0,
            tag .. ": common action " .. key .. " carries the client's spell name")
        if type(action.names) == "table" then
            for j = 1, #action.names do
                check(type(action.names[j]) == "string" and action.names[j] ~= "",
                    tag .. ": common action " .. key .. " names the client's spell")
            end
        end
        check(type(action.ids) == "table" and #action.ids > 0,
            tag .. ": common action " .. key .. " cites a spell id")
        if type(action.ids) == "table" then
            for j = 1, #action.ids do
                check(type(action.ids[j]) == "number",
                    tag .. ": common action " .. key .. " cites a numeric spell id")
            end
        end
        if type(action.families) == "table" then
            for j = 1, #action.families do
                check(FAMILY_PROJECT[action.families[j]] ~= nil,
                    tag .. ": common action " .. key .. " gates on a known family")
            end
        end
    end
end

-- The class's own alias table (the spellings the engine or the sim may report,
-- mapped onto the canonical key). The paladin publishes one; the other classes
-- use one key space, so they have none.
local function alias_of(M)
    local aliases = M.practice_action_aliases
    if type(aliases) ~= "table" then return function(k) return k end end
    return function(k) return aliases[k] or k end
end

--=========================================================================================
-- The walk
--=========================================================================================
for class_key, spec in pairs(CLASSES) do
    for _, slice in ipairs(spec.slices) do
        local tag = class_key .. "/" .. slice.id .. "@" .. slice.family
        local sb = build_slice(spec, slice)
        local st, ST = sb.st, sb.ST
        local M = ST[class_key]
        check(type(M) == "table", tag .. ": the class module publishes a table")
        if type(M) == "table" then
            local published = M.practice_neutral_actions
            check(type(published) == "table",
                tag .. ": the class publishes ST." .. class_key .. ".practice_neutral_actions")

            -- 1) the publish shape: a flat key -> true set, or a family-scoped
            --    family key -> set. Nothing else.
            local family_scoped = false
            if type(published) == "table" then
                for _, value in pairs(published) do
                    if type(value) == "table" then family_scoped = true end
                end
            end
            if type(published) == "table" then
                for key, value in pairs(published) do
                    if type(key) == "string" and key ~= "" then
                        if family_scoped then
                            check(type(value) == "table",
                                tag .. ": the family bucket " .. key .. " is a set")
                            if type(value) == "table" then
                                for k2, v2 in pairs(value) do
                                    check(type(k2) == "string" and k2 ~= "" and v2 == true,
                                        tag .. ": the family bucket " .. key .. " holds key = true entries")
                                end
                            end
                        else
                            check(value == true,
                                tag .. ": the published key " .. key .. " is exactly true")
                        end
                    end
                end
            end

            -- 2) the resolved neutral set for this family (the engine's own rule)
            local neutral = published_neutral_set(published, slice.family)
            local expected_neutral = keyset(slice.neutral)
            local same = same_set(neutral, expected_neutral)
            check(same, tag .. ": the published neutral set is exactly {"
                .. table.concat(slice.neutral, ", ") .. "}")
            if not same then
                print("      published: " .. table.concat(sorted(neutral), ", "))
            end

            -- 3) the rotation slice and the panel vocabulary
            local slice_keys = {}
            local entries = rotation_slice(M, class_key, slice)
            check(type(entries) == "table", tag .. ": the class publishes a rotation slice")
            if type(entries) == "table" then
                for i = 1, #entries do
                    local e = entries[i]
                    if type(e) == "table" and type(e.action) == "string" then
                        slice_keys[e.action] = true
                    end
                end
            end
            local slot_keys = guide_slot_keys(M, class_key, slice)
            local grid_keys = sim_grid_keys(st, class_key)
            local drill_keys = drill_grid_keys(M, class_key)
            local norm = alias_of(M)
            local common_keys = common_action_keys(M, slice, neutral, slice_keys, norm)
            local panel = {}
            for k in pairs(slice_keys) do panel[k] = true end
            for k in pairs(slot_keys) do panel[k] = true end
            for k in pairs(grid_keys) do panel[k] = true end
            for k in pairs(drill_keys) do panel[k] = true end
            for k in pairs(common_keys) do panel[k] = true end
            check(next(panel) ~= nil, tag .. ": the panel vocabulary is not empty")

            -- The class's published practice-panel ability list (the cited ids, the
            -- labels and the family gates).
            check_common_actions(tag, M)

            -- 4) THE GRADING-INTEGRITY PIN: no neutral key is a rotation action
            --    on this slice.
            for key in pairs(neutral) do
                check(slice_keys[norm(key)] ~= true,
                    tag .. ": the neutral key " .. key .. " is not a rotation action (a rotation"
                    .. " action can never be neutral)")
            end

            -- 4b) THE OFFER PINS (the orchestrator's ruling, 2026-10-20): an ability
            --      may only be OFFERED on a family where it is either a rotation
            --      action or a neutral action. An offer that can only ever be a
            --      mis-pick is a trap - the player is invited to press something the
            --      grader will always punish. So the panel's offer list and the
            --      neutral set are ONE truth per family: an ability with no neutral
            --      bucket on that family is NOT offered there (it stays available on
            --      the families where it IS neutral).
            --
            --      The class's OWN offer list is the thing under test: the list its
            --      practice_panel_slots hands to the panel (the practice panel reads
            --      the guide's slot list live).
            local offered = {}
            local panel_slots = M.practice_panel_slots()
            if type(panel_slots) == "table" then
                for i = 1, #panel_slots do
                    local slot = panel_slots[i]
                    if type(slot) == "table" and slot.practice_common == true
                        and type(slot.key) == "string" then
                        offered[slot.key] = true
                    end
                end
            end
            for key in pairs(offered) do
                -- The ruling's rule, in its own words: an offered ability is either
                -- a rotation action or a neutral action on this family.
                check(neutral[key] == true or slice_keys[norm(key)] == true,
                    tag .. ": the offered common ability " .. key
                    .. " is either a rotation action or a neutral action on this family"
                    .. " (an offer that can only ever be a mis-pick is a trap)")
                -- The class's own contract on top of it: the common-ability list is
                -- the class's statement of the abilities the rotation NEVER grades,
                -- so an offered ability is neutral here and NOT rotation-ranked.
                check(slice_keys[norm(key)] ~= true,
                    tag .. ": the panel offers the common ability " .. key
                    .. " only where the rotation does not ask for it")
                check(common_keys[key] == true,
                    tag .. ": the offered common ability " .. key
                    .. " is one the class's own data offers on this family")
            end
            -- 4c) THE DATA PIN: the class's own published set and its own ability
            --      list must agree. Where the class publishes a bucket for this
            --      family, every common ability the class's list names (and whose
            --      own family gate allows this family) must be in that bucket -
            --      unless the rotation ranks it there. A bucket that dropped such a
            --      key would leave the class's own data offering an ability the
            --      family does not publish: the mis-pick trap, in the data.
            if next(neutral) ~= nil then
                local list = M.practice_common_actions
                if type(list) == "table" then
                    for i = 1, #list do
                        local action = list[i]
                        if type(action) == "table" and type(action.key) == "string" then
                            local gated = true
                            if type(action.families) == "table" then
                                gated = false
                                for f = 1, #action.families do
                                    if action.families[f] == slice.family then
                                        gated = true
                                    end
                                end
                            end
                            if gated and slice_keys[norm(action.key)] ~= true then
                                check(neutral[action.key] == true,
                                    tag .. ": the common ability " .. action.key
                                    .. " is published as neutral on this family"
                                    .. " (the class's own list offers it here)")
                            end
                        end
                    end
                end
            end

            -- The other direction: an ability the rule offers (the class publishes
            -- it as neutral here, the rotation does not rank it, and the client has
            -- the spell) must REACH the panel. An ability the client does not have
            -- is dropped (unknown-hides) and is never offered - that is the class's
            -- own resolver answering.
            local common_list = M.practice_common_actions
            if type(common_list) == "table" and type(M.resolve_practice_common_action) == "function" then
                for i = 1, #common_list do
                    local action = common_list[i]
                    if type(action) == "table" and type(action.key) == "string"
                        and common_keys[action.key] == true then
                        local resolves = M.resolve_practice_common_action(action) ~= nil
                        if resolves then
                            check(offered[action.key] == true,
                                tag .. ": the common ability " .. action.key
                                .. " is published as neutral on this family and the client has it,"
                                .. " so the panel offers it")
                        end
                    end
                end
            end

            -- 5) THE CLOSED LIST: every panel key is classified exactly once -
            --    a rotation action, a neutral action, or an intentional mis-pick.
            local mispick = {}
            for key in pairs(panel) do
                if slice_keys[norm(key)] then
                    check(neutral[key] ~= true,
                        tag .. ": the rotation action " .. key .. " is not published as neutral")
                elseif neutral[key] then
                    check(mispick[key] ~= true,
                        tag .. ": the neutral key " .. key .. " is not also an intentional mis-pick")
                else
                    mispick[key] = true
                end
            end
            local expected_mispick = keyset(slice.mispick)
            local same_mis = same_set(mispick, expected_mispick)
            check(same_mis, tag .. ": the intentional mis-pick list is exactly {"
                .. table.concat(slice.mispick, ", ") .. "} (every panel key is classified)")
            if not same_mis then
                print("      found: " .. table.concat(sorted(mispick), ", "))
            end

            -- 6) every neutral key is a key the class's OWN ability list offers
            --    (the panel vocabulary) - no invented key.
            for key in pairs(neutral) do
                check(panel[key] == true,
                    tag .. ": the neutral key " .. key .. " is a key of the class's own panel")
            end

            -- 7) the shared engine's own reader (when the engine publishes it):
            --    the class's publish must resolve to the family's set.
            local H = st.practice and st.practice.harness
            if type(H) == "table" and type(H.practice_neutral_actions) == "function" then
                local ok, resolved = pcall(H.practice_neutral_actions, class_key)
                check(ok, tag .. ": the engine's neutral reader does not throw")
                if ok then
                    if next(expected_neutral) == nil then
                        check(resolved == nil,
                            tag .. ": the engine resolves no neutral set for this family")
                    else
                        check(type(resolved) == "table",
                            tag .. ": the engine resolves a neutral set for this family")
                        if type(resolved) == "table" then
                            local same_res = same_set(resolved, expected_neutral)
                            check(same_res, tag .. ": the engine resolves the published neutral set")
                            if not same_res then
                                print("      resolved: " .. table.concat(sorted(resolved), ", "))
                            end
                        end
                    end
                end
            end
        end
    end
end

--=========================================================================================
-- The publish is family-scoped only where the class needs it: a FLAT publish
-- carries the same set on every family, and a family-scoped publish must not
-- carry a bucket for a family the class never plays.
--=========================================================================================
for class_key, spec in pairs(CLASSES) do
    local sb = build_slice(spec, spec.slices[1])
    local published = sb.ST[class_key].practice_neutral_actions
    check(type(published) == "table", class_key .. ": the publish is a table")
    if type(published) == "table" then
        local family_scoped = false
        for _, value in pairs(published) do
            if type(value) == "table" then family_scoped = true end
        end
        if family_scoped then
            for key in pairs(published) do
                check(FAMILY_PROJECT[key] ~= nil,
                    class_key .. ": the family bucket " .. tostring(key) .. " is a known family")
            end
        else
            -- a flat publish: every published key must be neutral on EVERY slice
            for _, slice in ipairs(spec.slices) do
                for key in pairs(published) do
                    local listed = false
                    for _, k in ipairs(slice.neutral) do
                        if k == key then listed = true end
                    end
                    check(listed,
                        class_key .. ": the flat neutral key " .. key .. " is neutral on "
                        .. slice.id .. "@" .. slice.family)
                end
            end
        end
    end
end

--=========================================================================================
-- The WIDENING SEAM: the class appends its common abilities to its OWN guide slot
-- list, so the practice panel's action row offers them (the shaman's
-- apply_family_slots precedent - the guide frame keeps the icons it already built,
-- the panel reads the slot list live).
--
-- The sandbox's client answers the SPELL IDS and never the names, so the resolution
-- falls back to the cited id ladder - exactly the locale fallback the class
-- publishes. On the TBC slice the client answers names only, so nothing resolves
-- there and the panel stays narrow (unknown-hides, never a guess).
--=========================================================================================
for class_key, spec in pairs(CLASSES) do
    local slice = spec.slices[1]
    local sb = build_slice(spec, slice)
    local ST = sb.ST
    local M = ST[class_key]
    check(type(M) == "table", class_key .. ": the class module publishes a table")
    if type(M) == "table" then
        check(type(M.practice_panel_slots) == "function",
            class_key .. ": the class publishes the panel slot list")
        check(type(M.apply_practice_panel_actions) == "function",
            class_key .. ": the class publishes the widening seam")
        local common = M.practice_common_actions
        -- The common abilities the PANEL offers on this slice: the class's own
        -- OFFER GATE first (the published neutral set for this family carries the
        -- key and the rotation does not rank it - the same rule the class's own
        -- gate reads), then the resolution (an ability the running client does not
        -- have is never offered).
        local slice_neutral = published_neutral_set(M.practice_neutral_actions, slice.family)
        local slice_keys = {}
        local entries = rotation_slice(M, class_key, slice)
        if type(entries) == "table" then
            for i = 1, #entries do
                local e = entries[i]
                if type(e) == "table" and type(e.action) == "string" then
                    slice_keys[e.action] = true
                end
            end
        end
        local modelled = common_action_keys(M, slice, slice_neutral, slice_keys, alias_of(M))
        local resolvable = 0
        if type(common) == "table" then
            for i = 1, #common do
                local action = common[i]
                if type(action) == "table" and modelled[action.key] == true
                    and M.resolve_practice_common_action(action) ~= nil then
                    resolvable = resolvable + 1
                end
            end
        end
        local before = 0
        if type(M.guide) == "table" and type(M.guide.slots) == "table" then
            before = #M.guide.slots
        end
        local widened = M.practice_panel_slots()
        check(type(widened) == "table",
            class_key .. ": the panel slot list is a table")
        check(#widened == before + resolvable,
            class_key .. ": the panel slot list carries the common abilities the client has")
        M.apply_practice_panel_actions()
        local after = 0
        if type(M.guide) == "table" and type(M.guide.slots) == "table" then
            after = #M.guide.slots
        end
        check(after == before + resolvable,
            class_key .. ": the widening seam appends the common abilities to the slot list")
        -- The seam is idempotent (a second call must not double the common slots).
        M.apply_practice_panel_actions()
        local again = 0
        if type(M.guide) == "table" and type(M.guide.slots) == "table" then
            again = #M.guide.slots
        end
        check(again == after, class_key .. ": the widening seam is idempotent")
    end
end

--=========================================================================================
-- THE HARNESS REGISTRY GUARD MUST NOT BE SELF-REFERENTIAL
--
-- tests/toc_check.lua carries the "every suite on disk is registered in tests/run.sh"
-- guard. Deleting THAT one registry line in tests/run.sh disables the whole
-- guarantee while the harness still prints green - the registry line count falls by
-- one and nothing checks the guard any more. This suite carries the counter-guard:
-- it fails when tests/run.sh no longer registers the suite that carries the guard.
--
-- The two guards are MUTUAL, so neither can be switched off alone:
--   * delete THIS suite's registry line and toc_check's "every suite on disk is
--     registered" guard fails (this suite is on disk and unregistered);
--   * delete toc_check's registry line and the counter-guard below fails.
--
-- The step-count FLOOR is a ratchet, not an equality: a legitimate suite ADDITION
-- raises the count and passes, and a deleted registry line lowers it and fails. A
-- legitimate REMOVAL lowers the floor in the same change that removes the suite.
--
-- The floor is the number of suites the registry holds today (41); the harness
-- prints two more steps than that (the luac5.1 syntax step and the luacheck step).
--=========================================================================================
local REGISTRY_SUITE_FLOOR = 41

do
    local fh = io.open(ROOT .. "tests/run.sh", "r")
    local text = fh and fh:read("*a") or ""
    if fh then
        fh:close()
    end
    check(fh ~= nil, "tests/run.sh is readable (the harness registry)")

    -- The registry lines: one 'run "lua5.1 tests/<suite>.lua" ...' line per suite.
    local registered = {}
    for line in text:gmatch("[^\n]+") do
        local path = line:match('run "lua5%.1 (tests/[%w_%-]+%.lua)"')
        if path then
            registered[path] = (registered[path] or 0) + 1
        end
    end

    -- THE COUNTER-GUARD: the suite that carries the registry guard must be
    -- registered, and registered exactly once.
    check((registered["tests/toc_check.lua"] or 0) == 1,
        "tests/run.sh registers the suite that carries the registry guard exactly once"
            .. " (tests/toc_check.lua: "
            .. tostring(registered["tests/toc_check.lua"] or 0) .. ")")

    -- The step-count floor: a deleted registry line lowers the count and fails; a
    -- legitimate suite addition raises it and passes.
    local count = 0
    for _ in pairs(registered) do
        count = count + 1
    end
    check(count >= REGISTRY_SUITE_FLOOR,
        "the harness registry holds at least " .. tostring(REGISTRY_SUITE_FLOOR)
            .. " registered suites (" .. tostring(count) .. ")")
end

if failures == 0 then
    print("PASS  neutral_actions_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  neutral_actions_state.lua: " .. tostring(failures) .. " of "
        .. tostring(checks) .. " checks failed")
    os.exit(1)
end
