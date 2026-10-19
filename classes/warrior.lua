--=========================================================================================
-- Module for Warrior-specific behaviours: the on-next-attack colours and Blood Surge glow,
-- plus (mirroring the shaman/hunter/druid/paladin ports of the reference) the warrior
-- tracker set - the Shield Block bar, the Slam cast bar, the Overpower dodge-proc flash,
-- the Rampage upkeep badge and the Deep Wounds / Sunder Armor / Rend / Thunder Clap /
-- (reference SuperSwingTimer_ClassMods.lua warrior block 1689-3333). The pure tracker
-- maths lives next to the widgets (this class has no separate pure module).
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LCG = LibStub("LibCustomGlow-1.0")
local LSM = LibStub("LibSharedMedia-3.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table

-- See compat.lua: restricted (secret) reads must degrade, never error. Exact no-op
-- where the probe is absent (classic clients).
local is_secret = issecretvalue or function()
    return false
end

--=========================================================================================
-- Spell data
--=========================================================================================
-- Heroic Strike, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank).
-- Mortal Strike (29707 / 30324) is deliberately NOT in this table: it outranks the TBC
-- Heroic Strike id, so get_family_spell_id would pick it there and query the wrong rage
-- cost.
local hs_ids = get_tab({
    47450, 47449, 25286, 11567, 11566,
    11565, 11564, 1608, 285, 284, 78
})

-- Cleave, all ranks.
local cleave_ids = get_tab({
    47520, 47519, 25231, 20569, 11609, 11608, 7369, 845
})

-- Cached current-rank ids, resolved once on first use.
local hs_current_id
local cleave_current_id

-- Bloodsurge (WotLK proc)
local bloodsurge_id = 46916

-- Overpower dodge-window length (reference State.lua:26). Declared up here
-- with the other aura ids: on_aura_change is defined before the
-- tracker-constant block below, and a later local would be invisible to it
-- (it would read a nil global instead).
local WARRIOR_OVERPOWER_PROC_WINDOW = 5.0

-- Rampage (TBC fury "stack to 5 then upkeep"): the buff id the aura scan matches,
-- the literal English fallback (the same convention as the Shield Block scan) and
-- the stack cap. Declared up here with the other aura ids: on_aura_change is
-- defined before the tracker-constant block below, and a later local would be
-- invisible to it (it would read a nil global instead).
local WARRIOR_RAMPAGE_SPELL_ID = 29838
local WARRIOR_RAMPAGE_NAME = "Rampage"
local WARRIOR_RAMPAGE_MAX_STACKS = 5

-- Battle Shout uptime (discover #9): rank ids carried with the other aura ids
-- (on_aura_change below reads them before the tracker-constant block is defined).
-- A remembered id is a rumor, so every rank here cites the client-family audit
-- page that confirmed it (bench/buildout_warrior_2026-10-17.md): 6673 / 5242 /
-- 6192 (classic + Forever pages), 11551 / 25289 / 2048 / 47436 (wotlk-classic
-- pages, up to rank 9). A rank id the running client does not know simply never
-- matches; the literal English fallback below still covers the buff, and a
-- localized client matches by the ids it does know (the Rampage scan's pattern).
local WARRIOR_BATTLE_SHOUT_IDS = get_tab({
    6673, 5242, 6192, 11551, 25289, 2048, 47436
})
local WARRIOR_BATTLE_SHOUT_NAME = "Battle Shout"
-- The fallback covers auras the client reports without an expiry (2 min is the
-- audit pages' classic/WotLK duration; the Forever client lists 3 min, so a
-- client that answers always wins and this only covers an omission).
local WARRIOR_BATTLE_SHOUT_FALLBACK = 120

-- Bloodthirst and Whirlwind, all ranks across the classic families (the TBC fury
-- core): rank 1 first, the WotLK max last; get_family_spell_id picks the highest
-- id that exists on the running client (the current rank). Ranks from other
-- expansions are simply absent from the client's spell data, so carrying the
-- full set is harmless.
local bt_ids = get_tab({
    30335, 23894, 23893, 23892, 23884, 23883, 23882, 23881
})
local ww_ids = get_tab({
    47436, 47435, 25208, 11585, 11584, 6795, 6794, 1680
})

-- Cached current-rank ids for the TBC guide reads, resolved once like hs/cleave.
local bt_current_id
local ww_current_id

-- The TBC fury guide reads (Bloodthirst/Whirlwind cooldowns+costs, the HS dump
-- floor, the HS-cancel cue) exist only on the TBC family (st.family from compat.lua, which loads
-- before every class module). Every other family feeds nil for those inputs, and
-- the new engine rules require known readings, so non-TBC clients keep the
-- legacy behaviour exactly; Retail stays as inert as before (its invisibility
-- still comes from the swing state in nextaction_ui.should_show, never from a
-- family gate here - the Forever client must keep working).
local is_tbc_guide = st.family == "TBC"

-- The Wrath guide reads (BT/WW cooldowns+costs with the 50-rage floor, the arms
-- upkeep/cooldown readers, the SoD-independent Sudden Death / Taste for Blood
-- aura flags) exist only on the WRATH family. Every other family feeds nil for
-- the Wrath-only inputs (the engine rules require known readings, so they stay
-- inert there); TBC/Era/Retail behaviour is untouched (their inputs never
-- change shape or value - the new fields simply read nil there too).
local is_wrath_guide = st.family == "WRATH"

-- The Era fury guide reads (same BT/WW cooldowns+costs, the Era HS dump floor,
-- the Era reserve window and the Era Execute-spam flag) exist only on the ERA
-- family. BT/WW are vanilla spells that exist on Era and resolve through the
-- same rank tables above. Every non-core family feeds nil for all of these, so
-- the engine rules stay inert there exactly like before; Retail/Forever
-- inertness is unchanged (swing state decides visibility, never a family gate
-- here). SoD shares the ERA token and is detected per client via the rune
-- knowledge probe below (Raging Blow / Consumed by Rage through
-- api.is_spell_known): SoD feeds floor 60, the Era window, spam, the Sudden
-- Death bypass and the Raging Blow reader; Era-base feeds floor 30 and no SoD
-- flag.
local is_era_guide = st.family == "ERA"

-- The Forever guide reads (st.family == "FOREVER", the WoW Forever / Camelot
-- 1.60.x client): Bloodthrill arms the Overpower window through the aura scan
-- below (a second OP source alongside the classic dodge window, which can never
-- arm on Mainline-code clients), and Victory Rush feeds the engine's
-- victory_rush input when the family + knowledge + usable probe answers
-- (UNCONFIRMED id below). Every other family feeds nil for both, so the engine
-- stays byte-identical there; Retail keeps its swing-decided invisibility.
local is_forever_guide = st.family == "FOREVER"

-- Era fury tuning (sourced ground truth for the 1.15.9 fury priority:
-- Bloodthirst on CD > Whirlwind on CD > Heroic Strike dump only with rage to
-- spare (>= 30) and 2-3 s until next BT/WW, Execute spam below 20 %,
-- Overpower if specced). The window is the midpoint of the 2-3 s ground-truth
-- buffer; in-game tuning may move it to 2 or 3.
local ERA_HS_FLOOR = 30
local ERA_CORE_RESERVE_WINDOW = 2.5

-- Mortal Strike ranks for the arms/fury spec probe (Mortal Strike known =
-- arms): the Taste for Blood affected-spells list (wowhead.com/wotlk/
-- spell=56638). Deliberately a separate table: these ids must never enter
-- hs_ids above (the 29707/30324 comment). Only api.is_spell_known reads this
-- table (knowledge, not spell-data existence), so rank gaps across families
-- simply answer false.
local ms_ids = { 12294, 21551, 21552, 21553, 25248, 30330, 47485, 47486 }

-- Bladestorm (63784, wowhead.com/wotlk/spell=63784): the arms cooldown slot.
-- Single rank; knowledge-gated (untalented clients never prompt it).
local bladestorm_id = 63784

-- SoD runes (SoD detection: ERA family + one of these known via
-- api.is_spell_known): Raging Blow 402911 (wowhead.com/classic/
-- spell=402911, the SoD rune filler) and Consumed by Rage 425440
-- (wowhead.com/classic/spell=425440, the rage->60 pool buff).
local raging_blow_id = 402911
local consumed_by_rage_id = 425440

-- Sudden Death proc aura (the Execute enabler): 52437 on Wrath
-- (wowhead.com/wotlk/spell=52437, 10 s, Execute at any health) and 440495
-- plus the literal English fallback on SoD (in-game to confirm which SoD aura
-- id fires there).
local WARRIOR_SD_AURA_IDS = { 52437, 440495 }
local WARRIOR_SD_AURA_NAME = "Sudden Death"

-- Taste for Blood proc aura (the arms Overpower enabler without a dodge):
-- 60503 (the 9 s proc from wowhead.com/wotlk/spell=56638) plus the literal
-- English fallback. Rend-tick inference is deferred (no tick state yet).
local WARRIOR_TFB_AURA_ID = 60503
local WARRIOR_TFB_AURA_NAME = "Taste for Blood"

-- Bloodthrill (Forever arms Overpower enabler without a dodge, forever_beta.md:
-- beta guides name the talent but no spell/aura id - UNCONFIRMED, in-game to
-- confirm). No numeric id is carried on purpose: a guessed id could arm the
-- window on the wrong aura. The scan matches the literal aura name below, gated
-- on the FOREVER family, so every other family ignores the name entirely.
local WARRIOR_BLOODTHRILL_AURA_NAME = "Bloodthrill"

-- Victory Rush (Forever execute-phase cue, forever_beta.md: beta guides list
-- the spell but no id - 34428 is the WotLK Victory Rush id, carried here
-- UNCONFIRMED for the Forever client, in-game to confirm). The name fallback
-- mirrors the Bloodthrill aura-name match above: a wrong id degrades to the
-- name read instead of disabling the cue. The gather requires family +
-- (id-known or name-known) + usable, so a wrong id fails safe to nil on a
-- client that knows neither (never prompts).
local WARRIOR_VICTORY_RUSH_SPELL_ID = 34428 -- UNCONFIRMED on Forever
local WARRIOR_VICTORY_RUSH_NAME = "Victory Rush" -- UNCONFIRMED on Forever

-- Spec probe (Mortal Strike known = arms): walks ms_ids through
-- api.is_spell_known (knowledge, never spell-data existence). Cheap probe
-- chain; the slot/flag freeze happens once in post_init (see
-- resolve_guide_slots), so a mid-session respec needs /reload to re-pick the
-- slot set.
local function is_arms_spec()
    for i = 1, #ms_ids do
        if api.is_spell_known(ms_ids[i]) then
            return true
        end
    end
    return false
end

-- SoD probe (ERA family only): either SoD rune known. Same freeze rule as the
-- spec probe: a rune (un)learned mid-session needs /reload.
local function is_sod_client()
    if not is_era_guide then
        return false
    end
    return api.is_spell_known(raging_blow_id)
        or api.is_spell_known(consumed_by_rage_id)
end

-- Resolves the highest rank that exists on the running client exactly once. A negative
-- result is latched as false too, so a client without the spell stops re-walking the
-- whole table on every power tick.
local function resolve_rank(ids, cached)
    if cached == nil then
        return api.get_family_spell_id(ids) or false
    end
    return cached
end

-- One ability's rage cost from a GetSpellPowerCost result, with a restricted (secret)
-- reading treated as "the client cannot answer": the engine must never compare against
-- an opaque value (type() reports "number" for one, so a type guard cannot catch it).
-- A false from the caller's `rank and api.GetSpellPowerCost(...)` short-circuit (an
-- unresolved rank) normalises to nil too, the one "no cost" shape the engine expects.
local function rage_cost_of(costs)
    local cost = costs and costs[1] and costs[1].cost
    if is_secret(cost) then
        return nil
    end
    return cost or nil
end

-- Compares the current rage against the queued ability cost and recolours only when the
-- state actually changes: UNIT_POWER_FREQUENT fires several times a second.
local function update_rage_state(self, spell_id)
    local costs = spell_id and api.GetSpellPowerCost(spell_id)
    local rage_cost = rage_cost_of(costs)
    local power = api.UnitPower("player")
    -- No cost data (unlearned spell, client we cannot read) means we cannot claim the
    -- player is short of rage; a non-numeric reading (or a secret value on a modern
    -- client) degrades the same way instead of erroring on the comparison.
    local insufficient = false
    if type(rage_cost) == "number" and type(power) == "number" then
        insufficient = power < rage_cost
    end
    if self.insufficient_rage ~= insufficient then
        self.insufficient_rage = insufficient
        self:set_bar_color("mainhand")
    end
end

function ST.WARRIOR.on_rage_update(self)
    if self.hs_queued then
        hs_current_id = resolve_rank(hs_ids, hs_current_id)
        return update_rage_state(self, hs_current_id or nil)
    end
    if self.cleave_queued then
        cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
        return update_rage_state(self, cleave_current_id or nil)
    end
    -- Nothing queued: clear a stale "insufficient rage" colour left by the last fight.
    if self.insufficient_rage then
        self.insufficient_rage = false
        self:set_bar_color("mainhand")
    end
end

function ST.WARRIOR.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    if hs_ids[spell_id] ~= nil then
        self.hs_queued = false
        self:set_bar_color("mainhand")
        return
    end
    if cleave_ids[spell_id] ~= nil then
        self.cleave_queued = false
        self:set_bar_color("mainhand")
        return
    end
end

function ST.WARRIOR.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    -- print(unit_target)
    -- print(spell_id)
    -- A landed Overpower closes the dodge window so the flash reflects current usability
    -- (reference SuperSwingTimer.lua:1415-1421). The matcher only runs while the window
    -- is open, so an ordinary fight costs nothing here.
    if self.warrior_overpower_proc_until ~= nil
        and self.WARRIOR.is_overpower_cast(spell_id, cast_guid, api.get_time()) then
        self.warrior_overpower_proc_until = nil
    end
    if hs_ids[spell_id] ~= nil then
        self.hs_queued = false
        self:set_bar_color("mainhand")
        return
    end
    if cleave_ids[spell_id] ~= nil then
        self.cleave_queued = false
        self:set_bar_color("mainhand")
        return
    end
end

function ST.WARRIOR.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a heroic strike or cleave
    -- and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()

    -- Only run this logic if special on-next-attack colors are enabled in the warrior settings.
    if (not db.enable_hs_color) and not (db.enable_cleave_color) then
        return
    end

    if db.enable_hs_color then
        for spell_id in pairs(hs_ids) do
            local result = api.IsCurrentSpell(spell_id)
            if result then
                -- print('matched HS id: '..tostring(spell_id))
                self.hs_queued = true
                self.cleave_queued = false
                self:set_bar_color("mainhand")
                return
            end
        end
        self.hs_queued = false
    end

    -- No HS queued. Only probe Cleave when its colour is enabled, so the flag can never
    -- stay stale while the option is off.
    if not db.enable_cleave_color then
        self.cleave_queued = false
        return
    end
    for spell_id in pairs(cleave_ids) do
        local result = api.IsCurrentSpell(spell_id)
        if result then
            -- print('matched cleave id: '..tostring(spell_id))
            self.cleave_queued = true
            self:set_bar_color("mainhand")
            return
        end
    end
    self.cleave_queued = false
end

function ST.WARRIOR.on_aura_change(self)
    self.has_bloodsurge = false
    -- Sudden Death / Taste for Blood ride the same walk (no extra client
    -- reads): presence only, like has_bloodsurge. The gather maps them into
    -- the engine's sudden_death / tfb inputs (true or nil). Bloodthrill rides
    -- along too (Forever only, UNCONFIRMED name): it arms the Overpower window
    -- below instead of feeding the engine, so no new input is needed for it.
    local sd_found, tfb_found, bloodthrill_found = false, false, false
    -- The Rampage upkeep state rides the same walk (no extra client reads): the
    -- first matching aura's stack count, clamped to the 5-stack cap, and its
    -- expiration stamp for the badge's refresh window. A count the client omits
    -- still means one stack (the shaman's max(1, count) handling).
    local rampage_stacks, rampage_expires = nil, nil
    -- Battle Shout uptime rides the same walk (no extra client reads): the
    -- later-expiring matching aura stamp - or, when the client omits the expiry,
    -- now + the audit fallback duration - feeds the badge's countdown. Cleared
    -- whenever the buff is absent; never cleared in on_combat_exit (the buff
    -- persists between fights).
    local battle_shout_expires = nil
    -- Iterate all player auras
    local i = 1
    while true do
        -- "HELPFUL" explicitly: the Retail wrapper forwards the filter into
        -- C_UnitAuras.GetAuraDataByIndex, where it is a typed enum argument.
        local name, _, count, _, _, expiration, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
        if name == nil then
            break
        end
        if spell_id == bloodsurge_id then
            self.has_bloodsurge = true
        end
        if spell_id == WARRIOR_SD_AURA_IDS[1] or spell_id == WARRIOR_SD_AURA_IDS[2]
            or name == WARRIOR_SD_AURA_NAME then
            sd_found = true
        end
        if spell_id == WARRIOR_TFB_AURA_ID or name == WARRIOR_TFB_AURA_NAME then
            tfb_found = true
        end
        if name == WARRIOR_BLOODTHRILL_AURA_NAME then
            bloodthrill_found = true
        end
        if rampage_stacks == nil
            and (spell_id == WARRIOR_RAMPAGE_SPELL_ID or name == WARRIOR_RAMPAGE_NAME) then
            local n = tonumber(count) or 1
            if n < 1 then
                n = 1
            elseif n > WARRIOR_RAMPAGE_MAX_STACKS then
                n = WARRIOR_RAMPAGE_MAX_STACKS
            end
            rampage_stacks = n
            if type(expiration) == "number" and expiration > 0 then
                rampage_expires = expiration
            end
        end
        -- Battle Shout: rank ids first, then the literal English fallback (the
        -- Rampage scan's convention). The later-expiring stamp wins; a client
        -- that reports no expiry still arms the audit-duration shadow.
        if (spell_id and WARRIOR_BATTLE_SHOUT_IDS[spell_id])
            or name == WARRIOR_BATTLE_SHOUT_NAME then
            local bs_expires
            if type(expiration) == "number" and expiration > 0 then
                bs_expires = expiration
            else
                bs_expires = api.get_time() + WARRIOR_BATTLE_SHOUT_FALLBACK
            end
            if battle_shout_expires == nil or bs_expires > battle_shout_expires then
                battle_shout_expires = bs_expires
            end
        end
        i = i + 1
    end
    self.warrior_rampage_stacks = rampage_stacks
    self.warrior_rampage_expires = rampage_expires
    self.warrior_battle_shout_expires = battle_shout_expires
    self.has_sudden_death = sd_found
    self.has_tfb = tfb_found
    -- Forever Bloodthrill (UNCONFIRMED name): a second Overpower source. The
    -- classic dodge window can never arm on Mainline-code clients (main.lua
    -- never registers the combat log there), so on Forever this aura is the
    -- only OP source; every other family ignores the name entirely (the gate
    -- above). The window lapses on its own once the aura is gone, exactly
    -- like the dodge window.
    if is_forever_guide and bloodthrill_found then
        self.warrior_overpower_proc_until = api.get_time() + WARRIOR_OVERPOWER_PROC_WINDOW
    end
    self.WARRIOR.process_bloodsurge(self)
end

function ST.WARRIOR.glow_start(self)
    local db_class = self:get_class_table()
    local frame = self:get_bar_frame("mainhand")
    local db_hand = self:get_hand_table("mainhand")
    local thickness = db_hand.border_width or 1
    -- if thickness == 0 then
    --     thickness = 1
    -- end
    LCG.PixelGlow_Start(frame,
        {self:convert_color(db_class.bloodsurge_glow_color)},
        db_class.bloodsurge_glow_nlines,
        db_class.bloodsurge_glow_freq,
        db_class.bloodsurge_glow_line_length,
        thickness,
        0,
        0,
        false
    )
end

function ST.WARRIOR.process_bloodsurge(self)
    local db = self:get_class_table()
    local should_glow = (self.has_bloodsurge and db.use_bloodsurge_glow) and true or false
    -- LibCustomGlow pools its glow frames: re-starting (or stopping twice) on every aura
    -- event churns the pool and can double-release the frame, so only transition when
    -- the state actually changes.
    if should_glow == self.bloodsurge_glow_active then
        return
    end
    self.bloodsurge_glow_active = should_glow
    if should_glow then
        self.WARRIOR.glow_start(self)
    else
        self.WARRIOR.glow_stop(self)
    end
end

function ST.WARRIOR.glow_stop(self)
    local frame = self:get_bar_frame("mainhand")
    LCG.PixelGlow_Stop(frame)
end

function ST.WARRIOR.post_init(self)
    -- Starts settled so the first process_bloodsurge does not emit a spurious stop on
    -- an already-idle frame.
    self.bloodsurge_glow_active = false
    self.hs_queued = false
    self.cleave_queued = false
    self.insufficient_rage = false

    -- Tracker state (shared scan stamp, Shield Block cache, Slam cast window, Overpower
    -- proc window). The widgets live on the mainhand visuals frame; on_bar_update retries
    -- if it was not ready yet.
    self.warrior_scan_at = nil
    self.warrior_shield_block_duration = nil
    self.warrior_shield_block_expires = nil
    self.warrior_slam_casting = false
    self.warrior_slam_cast_start = nil
    self.warrior_slam_cast_duration = nil
    self.warrior_overpower_proc_until = nil
    self.warrior_overpower_flash_on = false
    self.warrior_rampage_stacks = nil
    self.warrior_rampage_expires = nil
    self.warrior_rampage_text_shown = nil
    -- Build-out round 1 state: the W3 tier colour currently applied to the
    -- badge, the W1 bank cue's visibility (churn-guarded) and the Battle Shout
    -- badge's shadow state (capture timestamp + last written read-out).
    self.warrior_rampage_tier_applied = nil
    self.warrior_bank_shown = false
    self.warrior_battle_shout_text_shown = nil
    self.warrior_battle_shout_expires = nil
    self.has_sudden_death = false
    self.has_tfb = false
    -- Frozen branch (Mortal Strike known = arms; ERA + SoD rune = SoD): the
    -- slot set and the engine flags freeze together here, so the two can never
    -- disagree about which actions exist. A respec or rune change mid-session
    -- needs /reload (see the guide header).
    self.warrior_is_arms = is_arms_spec()
    self.warrior_is_sod = is_sod_client()
    self.WARRIOR.resolve_guide_slots(self)
    self.WARRIOR.setup_warrior_visuals(self)

    -- Next Action Guide: resolve the guide's ability icons to the client's current ranks
    -- while the spell data is live, then hand the provider (ST.WARRIOR.guide at the end
    -- of this file) to the shared frame. Guarded so a flavor without nextaction_ui stays
    -- inert; the guide itself stays hidden until nextaction_enabled is turned on.
    self.WARRIOR.resolve_guide_icons()
    if st.nextaction_ui then
        st.nextaction_ui.init(self)
    end
    -- Cooldown HUD: builds its own UIParent frames (out of combat, deferred and
    -- retried via the per-frame hook under lockdown) from this class's HUD_SLOTS
    -- and the provider below; guarded so a flavor without hud.lua stays inert
    -- (the paladin wires it the same way in classes/paladin.lua).
    if st.hud then
        st.hud.init(self)
    end
end

function ST.WARRIOR.on_combat_exit(self)
    -- A queued ability dies with the fight; without this the bar can keep the HS /
    -- Cleave / insufficient-rage colour into the next pull. The same goes for an
    -- in-flight Slam cast and the Overpower dodge window (the reference clears
    -- warriorOverpowerProcUntil on PLAYER_REGEN_ENABLED, SuperSwingTimer.lua:1694).
    self.hs_queued = false
    self.cleave_queued = false
    self.insufficient_rage = false
    self.warrior_overpower_proc_until = nil
    self.warrior_slam_casting = false
    self.warrior_slam_cast_start = nil
    self.warrior_slam_cast_duration = nil
    self.WARRIOR.process_bloodsurge(self)
    if self.interfaces_are_initialised then
        self:set_bar_color("mainhand")
    end
end

function ST.WARRIOR.set_bar_color(self, hand)
    -- Returns true if any special setting was applied to let the parent func know
    -- to revert to default behaviour.
    -- Will set appropriate colors for HS/Cleave queued if requested in the settings,
    -- and will set a special color when the player has one of those queued up but has
    -- insufficient rage to cast them.
    local db_class = self:get_class_table()
    local frame = self:get_visuals_frame(hand)

    self.WARRIOR.process_bloodsurge(self)

    if hand ~= "mainhand" then
        return false
    end

    -- On-next-attack behaviours
    if db_class.enable_hs_color and self.hs_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.hs_color)
        )
        return true
    end
    if db_class.enable_cleave_color and self.cleave_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.cleave_color)
        )
        return true
    end

    -- Insufficient rage for queue.
    if (self.cleave_queued or self.hs_queued) and self.insufficient_rage then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.insufficient_rage_color)
        )
        return true
    end

    return false

end

--=========================================================================================
-- Warrior trackers (reference SuperSwingTimer_ClassMods.lua warrior block 1689-3333)
--=========================================================================================
-- The Shield Block duration bar, the Slam cast bar, the Overpower dodge-proc flash,
-- the Rampage upkeep badge, the Battle Shout badge, the W1 rage-bank cue and the
-- Deep Wounds / Sunder Armor / Rend / Thunder Clap / Demo Shout bars live here.
-- The pure maths lives next to the widgets (this class has no separate pure module):
-- ST.WARRIOR.get_debuff_remaining / should_debuff_glow / get_overpower_remaining /
-- is_overpower_cast / get_rampage_display / get_rampage_tier / get_bank_state /
-- get_battle_shout_display / composite_rage_gate / gate_composite_action are
-- directly unit-tested. One throttled scan (0.05 s) of the target's
-- harmful auras feeds all five debuff bars; the player's helpful auras are read on the
-- same cadence for Shield Block. Every read is gated on the options that consume it.

-- Slam, all ranks across the classic families. The same set the vendored
-- LibClassicSwingTimerAPI carries as pause_swing_spells (reference PAUSE_SWING_SPELLS,
-- SuperSwingTimer_Constants.lua:762-768; the WotLK ranks 47474/47475 come from the
-- library's own table, Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:1231-1240).
-- The localized-name fallback covers a rank the table misses.
local slam_ids = get_tab({ 47475, 47474, 25242, 25241, 11605, 11604, 8820, 1464 })

-- Overpower: the reference resolves rank 1 and matches the localized name for the other
-- ranks (Constants.lua:189-190; State.lua:1418-1421). Shield Block: the player's defensive
-- buff (SHIELD_BLOCK_ID/NAME, Constants.lua:261-262).
local overpower_id = 7384
local shield_block_id = 2565

-- Target debuff rank ids (reference SuperSwingTimer_Constants.lua:274-347). The
-- localized-name fallback below covers ranks added after the reference's table was
-- written (its own name fallbacks do the same).
local deep_wounds_ids = get_tab({ 12721 })
local sunder_armor_ids = get_tab({ 7386, 7405, 8380, 11596, 11597, 25225 })
-- Rend ranks: the vanilla set plus the WotLK max 47465 (15 s duration,
-- wowhead.com/wotlk/spell=47465). Wrath clients resolve the max; older
-- families never see that id, so carrying it is harmless (the BT/WW comment
-- above). The guide's arms upkeep reads through the same table.
local rend_ids = get_tab({ 772, 6546, 6547, 6548, 11572, 11573, 11574, 47465 })
local thunder_clap_ids = get_tab({ 6343, 8198, 8204, 8205, 11580, 11581 })
local demo_shout_ids = get_tab({ 1160, 6190, 11554, 11555, 11556 })

-- Scan/geometry constants (parenthesised line references are the reference's).
local WARRIOR_SCAN_INTERVAL = 0.05        -- 0.05 s scan cadence (ClassMods 2332, 2483, ...)
local WARRIOR_BAR_BOTTOM_GAP = 2          -- bottom slot above the bar (RestackDebuffBars gap)
local WARRIOR_BAR_STACK_GAP = 2           -- between stacked bars (same gap)
local WARRIOR_DEBUFF_HEIGHT = 6           -- all five reference debuff bars are 6 px
local WARRIOR_SHIELD_BLOCK_HEIGHT = 4     -- WARRIOR_SHIELD_BLOCK_BAR_HEIGHT (Constants.lua:166)
local WARRIOR_SLAM_HEIGHT = 4             -- the reference slam bar is 4 px (ClassMods.lua:1935)
local WARRIOR_GLOW_WINDOW = 4             -- glow inside the final 4 s (GLOW_WINDOW constants)
local WARRIOR_NAMES_RETRY_S = 5           -- localized-name retry cadence on a mute client
local WARRIOR_OP_EDGE_COLOR = { 1, 0.85, 0.10 }    -- Overpower glow edge (ClassMods.lua:1981)
local WARRIOR_OP_TEXT_COLOR = { 1.0, 0.95, 0.2, 1 } -- "OP" text (ClassMods.lua:2015)
local WARRIOR_OP_PULSE_HZ = 10                       -- sin(now * 10) pulse (ClassMods.lua:2027)
local WARRIOR_SHIELD_BLOCK_FALLBACK_COLOR = { 51, 140, 255, 0.90 } -- shieldBlockBar (Constants.lua:1006)
local WARRIOR_SLAM_LABEL_COLOR = { 1.0, 0.85, 0.15, 0.95 }         -- slam label (ClassMods.lua:1949)

-- Slam safe-window band (brainstorm W4): the Slam fill reads green when the
-- cast lands before the next swing and red when the swing lands mid-cast (the
-- cast resets into the deadzone). Drawn behind the existing slam-bar toggle
-- (no new option); on Forever every cast reads clean (Forever Slam never
-- resets the swing - the swing_resets == false path of the pure verdict).
local WARRIOR_SLAM_SAFE_COLOR = { 46, 204, 113, 1.0 }
local WARRIOR_SLAM_CLASH_COLOR = { 217, 38, 26, 0.90 }

-- Rampage upkeep badge (the Shamanistic Rage badge pattern in
-- classes/shaman.lua: a right-edge FontString with a countdown text).
local WARRIOR_RAMPAGE_BADGE_COLOR = { 255, 140, 26, 0.95 }

-- Rampage tier colours (buildout W3): the badge recolours by how well the
-- buff is maintained - green while the refresh window is far, amber inside
-- the final glow window, red inside the final 2 s. Green and amber reuse the
-- Slam safe-window colour and the badge's original colour; red is the Slam
-- clash hue at full alpha.
local WARRIOR_RAMPAGE_TIER_COLORS = {
    green = WARRIOR_SLAM_SAFE_COLOR,
    amber = WARRIOR_RAMPAGE_BADGE_COLOR,
    red = { 217, 38, 26, 1.0 },
}

-- W1 rage-bank cue (buildout W1): a 2 px amber top edge plus a centred "BANK"
-- label on the mainhand visuals frame while in combat the target sits inside
-- the pre-Execute band ([threshold, threshold + 15 %) - the band the verifier
-- described) and rage has reached the floor. Static powerset of the Overpower
-- flash (edge + centred text), no pulse: the cue is a sustained condition.
local WARRIOR_BANK_BAND = 15
local WARRIOR_BANK_RAGE_FLOOR = 60
local WARRIOR_BANK_EDGE_COLOR = { 255, 170, 0, 0.95 }
local WARRIOR_BANK_TEXT_COLOR = { 255, 170, 0, 1.0 }

-- Battle Shout uptime badge (the Rampage badge pattern, one widget above it).
local WARRIOR_BATTLE_SHOUT_BADGE_COLOR = { 240, 200, 60, 0.95 }

-- W2 composite fallback costs (verify §4.2 - BINDING): the class's known rank
-- costs stand in when a family's cooldown read answers but its power-cost read
-- stays muted (the gate then still protects the rage floor; the costs are the
-- vanilla-line Bloodthirst/Whirlwind ranks the classic families carry).
local WARRIOR_COMPOSITE_BT_COST = 30
local WARRIOR_COMPOSITE_WW_COST = 25

-- Ordered bottom-to-top exactly like the reference restack list (ClassMods.lua:3000-3005):
-- Deep Wounds, Sunder Armor, Rend, Thunder Clap, Demo Shout. Heights (6 px), fallback
-- durations (12 / 30 / 9 / 30 / 30 s) and fill colours (ClassMods.lua:2273, 2413, 2565,
-- 2705, 2844) are the reference's; the colours are stored in the class-option format
-- (0-255 RGB + 0-1 alpha, converted through the same convert_color path as the rest).
local warrior_debuff_defs = {
    {
        key = "deep_wounds",
        ids = deep_wounds_ids,
        fallback_names = { ["Deep Wound"] = true, ["Deep Wounds"] = true },
        fallback_duration = 12,
        option = "show_warrior_deep_wounds_bar",
        color_option = "warrior_deep_wounds_bar_color",
        fallback_color = { 179, 38, 38, 0.90 },
    },
    {
        key = "sunder_armor",
        ids = sunder_armor_ids,
        fallback_names = { ["Sunder Armor"] = true },
        fallback_duration = 30,
        label_mode = "stacks",
        option = "show_warrior_sunder_armor_bar",
        color_option = "warrior_sunder_armor_bar_color",
        fallback_color = { 140, 89, 38, 0.90 },
    },
    {
        key = "rend",
        ids = rend_ids,
        fallback_names = { ["Rend"] = true },
        fallback_duration = 9,
        option = "show_warrior_rend_bar",
        color_option = "warrior_rend_bar_color",
        fallback_color = { 217, 38, 26, 0.90 },
    },
    {
        key = "thunder_clap",
        ids = thunder_clap_ids,
        fallback_names = { ["Thunder Clap"] = true },
        fallback_duration = 30,
        option = "show_warrior_thunder_clap_bar",
        color_option = "warrior_thunder_clap_bar_color",
        fallback_color = { 89, 140, 191, 0.90 },
    },
    {
        key = "demo_shout",
        ids = demo_shout_ids,
        fallback_names = { ["Demoralizing Shout"] = true, ["Demoralising Shout"] = true },
        fallback_duration = 30,
        option = "show_warrior_demo_shout_bar",
        color_option = "warrior_demo_shout_bar_color",
        fallback_color = { 166, 128, 77, 0.90 },
    },
}

-- The bar's configured font, with the client standard font as the fallback for
-- sandboxes and stripped clients (same shape as the shaman/druid tracker helper).
local function get_tracker_font_path(self)
    local db_hand = self.get_hand_table and self:get_hand_table("mainhand")
    if LSM and LSM.Fetch and db_hand and db_hand.text_font then
        local path = LSM:Fetch("font", db_hand.text_font)
        if path then return path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

--=========================================================================================
-- Pure tracker maths (unit-tested directly by tests/warrior_state.lua)
--=========================================================================================

-- Remaining/total pair for a timed debuff bar: the fallback duration covers auras the
-- client reports without one; a listed-but-expired aura floors at 0 (the reference clamps
-- the same way, ClassMods.lua:2366-2369).
function ST.WARRIOR.get_debuff_remaining(aura_duration, aura_expiration, now, fallback_duration)
    local duration = tonumber(aura_duration)
    if not duration or duration <= 0 then
        duration = fallback_duration
    end
    local remaining = duration
    if type(aura_expiration) == "number" and aura_expiration > 0 then
        remaining = aura_expiration - now
        if remaining < 0 then
            remaining = 0
        end
    end
    return remaining, duration
end

-- The glow window: on inside the final 4 s of a still-running debuff, never at 0.
function ST.WARRIOR.should_debuff_glow(remaining)
    return type(remaining) == "number" and remaining > 0 and remaining <= WARRIOR_GLOW_WINDOW
end

-- Overpower proc countdown: the remaining seconds of the dodge window, or nil when it is
-- unset or already over.
function ST.WARRIOR.get_overpower_remaining(proc_until, now)
    if type(proc_until) ~= "number" then
        return nil
    end
    local remaining = proc_until - now
    if remaining <= 0 then
        return nil
    end
    return remaining
end

-- Rampage badge text: "RAMPAGE x<stacks> <seconds>s" while the buff is live, the
-- stacks-only form when the client reported no expiration, nil when the badge
-- should hide (no stacks, or the window already elapsed). The stack cap is
-- applied by the aura scan, never here, so this stays a pure formatter.
function ST.WARRIOR.get_rampage_display(stacks, expires, now)
    if type(stacks) ~= "number" or stacks < 1 then
        return nil
    end
    if type(expires) == "number" and expires > 0 then
        local remaining = expires - now
        if remaining <= 0 then
            return nil
        end
        return string.format("RAMPAGE x%d %.0fs", stacks, remaining)
    end
    return string.format("RAMPAGE x%d", stacks)
end

--=========================================================================================
-- Build-out round 1 pure helpers (referenced rows in bench/verify_bank.md);
-- all directly unit-tested in tests/warrior_state.lua
--=========================================================================================

-- Rampage refresh tier (buildout W3): the badge recolours by how well the buff
-- is maintained - nil with no buff, "red" inside the final 2 s, "amber" inside
-- the final glow window, "green" while well-maintained. A client that never
-- reported an expiry reads amber (the refresh window is unknown, not maintained).
function ST.WARRIOR.get_rampage_tier(stacks, expires, now)
    if type(stacks) ~= "number" or stacks < 1 then
        return nil
    end
    if type(expires) ~= "number" or expires <= 0 then
        return "amber"
    end
    local remaining = expires - now
    if remaining <= 2 then
        return "red"
    elseif remaining <= WARRIOR_GLOW_WINDOW then
        return "amber"
    end
    return "green"
end

-- W1 rage-bank state: true while in combat, the PLAYER'S health percentage sits
-- inside the pre-Execute band [threshold, threshold + band) and rage has reached
-- the floor. An unreadable health or rage never arms the cue: the state would
-- have to claim the band without seeing it, and a wrongly shown cue is costlier
-- than a missed one (the W2 gate degrades the opposite way on purpose - there
-- the withhold is the risk, here the false show is).
function ST.WARRIOR.get_bank_state(health_pct, execute_pct, rage, in_combat)
    if in_combat ~= true then
        return false
    end
    if type(health_pct) ~= "number" or type(execute_pct) ~= "number" then
        return false
    end
    if type(rage) ~= "number" or rage < WARRIOR_BANK_RAGE_FLOOR then
        return false
    end
    return health_pct >= execute_pct and health_pct < execute_pct + WARRIOR_BANK_BAND
end

-- W2 composite rage gate (verify §4.2 - BINDING): true when rage covers the
-- prompt's cost plus the reserve the composite must protect. Unknown reads
-- degrade to ALLOW (unknown is not a shortage - the rotation label pins that
-- Bloodthirst stays the default with no power read), so a nil cost or an
-- unknown reserve is treated as absent. The caller substitutes the class's
-- fixed fallback costs first (the authoritative rank cost on a muted client),
-- so in the composite path none of the costs are nil.
function ST.WARRIOR.composite_rage_gate(rage, cost, reserve)
    if type(rage) ~= "number" or type(cost) ~= "number" then
        return true
    end
    local reserved = type(reserve) == "number" and reserve or 0
    return rage >= cost + reserved
end

-- Cost substitute: a numeric client read wins, otherwise the documented fixed
-- cost (the reserve uses 0 - an unjudgeable read cannot reserve what it cannot
-- see, so the composite degrades to the ungated core comparison).
local function composite_cost(cost, fallback)
    if type(cost) == "number" then
        return cost
    end
    return fallback
end

-- The gate over the engine's composite pick (buildout W2): the engine orders
-- the TBC core by cooldown alone, so its Bloodthirst prompt can be fired while
-- the rage a queued Heroic Strike/Cleave needs is already promised. Only a
-- Bloodthirst prompt is re-judged (the engine's own HS-cancel cue and the rule
-- order it feeds the queue into keep the other actions coherent); a gated BT
-- falls back "BT first, WW next": Whirlwind is the next core, so the prompt
-- shifts to WW when that core is ready AND still affordable after the same
-- reserve - otherwise no prompt at all. Touches out.action only.
function ST.WARRIOR.gate_composite_action(inputs, out)
    if out.action ~= "bt" then
        return out
    end
    local reserve = 0
    if inputs.hs_queued == true then
        reserve = composite_cost(inputs.hs_cost, 0)
    elseif inputs.cleave_queued == true then
        reserve = composite_cost(inputs.cleave_cost, 0)
    end
    local bt_cost = composite_cost(inputs.bt_cost, WARRIOR_COMPOSITE_BT_COST)
    if ST.WARRIOR.composite_rage_gate(inputs.rage, bt_cost, reserve) then
        return out
    end
    local ww_cost = composite_cost(inputs.ww_cost, WARRIOR_COMPOSITE_WW_COST)
    if type(inputs.ww_remaining) == "number" and inputs.ww_remaining <= 0
        and ST.WARRIOR.composite_rage_gate(inputs.rage, ww_cost, reserve) then
        out.action = "ww"
    else
        out.action = nil
    end
    return out
end

-- Battle Shout badge text: "BS <seconds>s" while the buff's window is live,
-- nil when the badge should hide (no capture, or the window already elapsed).
-- The fallback shadow is applied by the aura scan, never here.
function ST.WARRIOR.get_battle_shout_display(expires, now)
    if type(expires) ~= "number" or expires <= 0 then
        return nil
    end
    local remaining = expires - now
    if remaining <= 0 then
        return nil
    end
    return string.format("BS %.0fs", remaining)
end

-- True when a successful-cast payload is an Overpower cast: the rank-1 id, the literal or
-- localized name token, or any rank whose resolved name matches (the reference matches id
-- + name, State.lua:1418-1421). The localized name is resolved lazily and never retried
-- into a hard failure: a client without the spell data simply never name-matches.
local overpower_name_resolved
local overpower_name_retry_at = 0

local function resolve_overpower_name(now)
    if overpower_name_resolved == nil and now >= overpower_name_retry_at then
        local name = api.GetSpellInfo(overpower_id)
        if name then
            overpower_name_resolved = name
        else
            overpower_name_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

function ST.WARRIOR.is_overpower_cast(spell_id, cast_guid, now)
    if spell_id == overpower_id or cast_guid == "Overpower" then
        return true
    end
    resolve_overpower_name(now)
    local name = overpower_name_resolved
    if name == nil then
        return false
    end
    if cast_guid == name then
        return true
    end
    if type(spell_id) == "number" then
        return api.GetSpellInfo(spell_id) == name
    end
    return false
end

--=========================================================================================
-- Throttled reads (one merged target scan + one player Shield Block read per window)
--=========================================================================================

-- Reused scan state: the per-window result of the merged target walk, keyed by debuff
-- key. Cleared and refilled per scan (assignments only, so the throttled scan path never
-- allocates beyond the localized-name table's first resolution).
local warrior_debuff_found = {}
local warrior_debuff_duration = {}
local warrior_debuff_expiration = {}
local warrior_debuff_stacks = {}

-- Resolve the client's own (localized) names for a debuff's rank ids, mirroring the
-- reference's ns.WARRIOR_*_NAME = GetSpellInfo(id) ... at load (Constants.lua:335, 341,
-- 347). Lazy: it only runs from the scan while a bar option is on, so an all-off
-- configuration reads nothing from the client. An unanswered client (spell data not up
-- yet) retries at a throttled cadence.
local function resolve_debuff_localized_names(def, now)
    local names = {}
    for id in pairs(def.ids) do
        local name = api.GetSpellInfo(id)
        if name then
            names[name] = true
        end
    end
    if next(names) ~= nil then
        def.localized_names = names
    else
        def.names_retry_at = now + WARRIOR_NAMES_RETRY_S
    end
end

-- One throttled walk of the target's harmful auras feeds all five debuff bars (the
-- reference walks once per bar, ClassMods.lua:2309-2327 etc.; one merged walk follows the
-- druid/shaman ports). Each aura matches by rank id first, then by the localized name
-- resolved from the client, then by the literal English fallback; the aura must belong to
-- the player. A target without matching auras - or no target at all, where UnitAura
-- answers nil - clears every slot. Stack counts are captured for every slot (Sunder
-- Armor's label shows one).
local function scan_target_warrior_debuffs(now)
    local found = warrior_debuff_found
    local duration = warrior_debuff_duration
    local expiration = warrior_debuff_expiration
    local stacks = warrior_debuff_stacks
    local pending = #warrior_debuff_defs
    for i = 1, #warrior_debuff_defs do
        local def = warrior_debuff_defs[i]
        local key = def.key
        found[key] = nil
        duration[key] = nil
        expiration[key] = nil
        stacks[key] = nil
        if def.localized_names == nil and now >= (def.names_retry_at or 0) then
            resolve_debuff_localized_names(def, now)
        end
    end
    local index = 1
    while index <= 40 and pending > 0 do
        local name, _, count, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("target", index, "HARMFUL")
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it, so a restricted row above the debuffs no longer
        -- truncates the scan.
        if name ~= nil then
            if source == "player" or source == nil then
                for i = 1, #warrior_debuff_defs do
                    local def = warrior_debuff_defs[i]
                    local key = def.key
                    if found[key] == nil then
                        local is_match = (type(spell_id) == "number" and def.ids[spell_id] ~= nil)
                            or def.fallback_names[name] == true
                            or (def.localized_names ~= nil and def.localized_names[name] == true)
                        if is_match then
                            found[key] = true
                            duration[key] = aura_duration
                            expiration[key] = aura_expiration
                            stacks[key] = tonumber(count)
                            pending = pending - 1
                        end
                    end
                end
            end
        end
        index = index + 1
    end
end

-- Shield Block read: one walk of the player's helpful auras, throttled with the debuff
-- scan. The localized name and the bar icon are resolved from the client's spell data
-- lazily (same cadence as the debuff names) so an option-off configuration never touches
-- GetSpellInfo.
local shield_block_name_resolved
local shield_block_icon_resolved
local shield_block_retry_at = 0

local function resolve_shield_block_info(now)
    if shield_block_name_resolved == nil and now >= shield_block_retry_at then
        local name, _, icon = api.GetSpellInfo(shield_block_id)
        if name then
            shield_block_name_resolved = name
            shield_block_icon_resolved = icon or false
        else
            shield_block_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

local function scan_player_shield_block(now)
    resolve_shield_block_info(now)
    local i = 1
    while i <= 40 do
        -- "HELPFUL" explicitly: the Retail wrapper forwards the filter into
        -- C_UnitAuras.GetAuraDataByIndex, where it is a typed enum argument.
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it.
        local name, _, _, _, duration, expiration, _, _, _, spell_id =
            api.UnitAura("player", i, "HELPFUL")
        if name ~= nil then
            if spell_id == shield_block_id
                or (shield_block_name_resolved ~= nil and name == shield_block_name_resolved)
                or name == "Shield Block" then
                return duration, expiration
            end
        end
        i = i + 1
    end
    return nil, nil
end

-- Slam name matching for payloads that carry a name token instead of an id: the client's
-- own localized names for the tracked ranks (resolved once, throttled while the client's
-- spell data is not up yet) plus the literal English fallback.
local slam_localized_names
local slam_names_retry_at = 0

local function resolve_slam_names(now)
    if slam_localized_names == nil and now >= slam_names_retry_at then
        local names = {}
        for id in pairs(slam_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                names[name] = true
            end
        end
        if next(names) ~= nil then
            slam_localized_names = names
        else
            slam_names_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

local function is_warrior_slam_token(token, now)
    if token == nil then
        return false
    end
    local id = tonumber(token)
    if id ~= nil then
        return slam_ids[id] == true
    end
    if token == "Slam" then
        return true
    end
    resolve_slam_names(now)
    return slam_localized_names ~= nil and slam_localized_names[token] == true
end

-- Queued-melee localized names (R1): the client's own names for every Heroic
-- Strike / Cleave rank, resolved once through GetSpellInfo and retried at the
-- shared throttled cadence while the client's spell data is not up yet (the
-- debuff-name discipline). Anniversary (UNCONFIRMED) may send the spell name
-- where classic sends the numeric id in the SPELL_MISSED dodge branch below.
local WARRIOR_HS_NAME = "Heroic Strike"
local WARRIOR_CLEAVE_NAME = "Cleave"
local hs_cleave_localized_names
local hs_cleave_names_retry_at = 0

local function resolve_hs_cleave_names(now)
    if hs_cleave_localized_names == nil and now >= hs_cleave_names_retry_at then
        local names = {}
        for id in pairs(hs_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                names[name] = true
            end
        end
        for id in pairs(cleave_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                names[name] = true
            end
        end
        if next(names) ~= nil then
            hs_cleave_localized_names = names
        else
            hs_cleave_names_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

local function is_warrior_queued_melee_proc_name(name, now)
    if name == WARRIOR_HS_NAME or name == WARRIOR_CLEAVE_NAME then
        return true
    end
    resolve_hs_cleave_names(now)
    return hs_cleave_localized_names ~= nil and hs_cleave_localized_names[name] == true
end

-- Fallback cast duration when the client has no live cast window: the resolved rank's
-- cast time from the client's spell data, else the reference's 1.5 s default
-- (GetSpellCastDuration, ClassMods.lua:1868-1877).
local function get_slam_fallback_duration()
    local id = api.get_family_spell_id(slam_ids)
    if id then
        local _, _, _, cast_ms = api.GetSpellInfo(id)
        if type(cast_ms) == "number" and cast_ms > 0 then
            return cast_ms / 1000
        end
    end
    return 1.5
end

--=========================================================================================
-- Slam cast tracking (state only; the widgets are drawn by the per-frame hook)
--=========================================================================================

-- The live cast window for the player, in the api.get_time() domain (the same reads the
-- shaman weave assist uses): name, spell id, start seconds, end seconds; nil when no cast
-- is running. UnitCastingInfo and UnitChannelInfo do NOT share a return shape: casting
-- returns castID before notInterruptible and the spell id 9th, channeling has no castID
-- and the spell id 8th.
local function get_live_player_cast()
    local name, _, _, start_ms, end_ms, _, _, _, spell_id = api.UnitCastingInfo("player")
    if type(start_ms) ~= "number" or type(end_ms) ~= "number" or end_ms <= start_ms then
        name, _, _, start_ms, end_ms, _, _, spell_id = api.UnitChannelInfo("player")
    end
    if type(start_ms) ~= "number" or type(end_ms) ~= "number" or end_ms <= start_ms then
        return nil, nil, nil, nil
    end
    return name, spell_id, start_ms / 1000, end_ms / 1000
end

-- Record the start (or delay) of a Slam cast. The client's live start/end window wins;
-- without one the duration falls back to the resolved rank's cast time (Improved Slam and
-- haste are only visible through the live window).
local function begin_warrior_slam_cast(self, live_start, live_end)
    local now = api.get_time()
    self.warrior_slam_casting = true
    if type(live_start) == "number" and type(live_end) == "number" and live_end > live_start then
        self.warrior_slam_cast_start = live_start
        self.warrior_slam_cast_duration = live_end - live_start
    else
        self.warrior_slam_cast_start = now
        self.warrior_slam_cast_duration = get_slam_fallback_duration()
    end
end

local function end_warrior_slam_cast(self)
    self.warrior_slam_casting = false
    self.warrior_slam_cast_start = nil
    self.warrior_slam_cast_duration = nil
end

-- Player spellcast lifecycle (dispatched from main.lua's UNIT_SPELLCAST_* handlers):
-- state-only, like the shaman weave tracker, so the hook is safe on every handler path
-- that reaches it. The option gate comes first, so an option-off configuration performs
-- no cast reads at all; the STOP family always clears, so a cast interrupted mid-flight
-- can never leave the bar stuck.
function ST.WARRIOR.on_spellcast_event(self, event, unit, cast_guid, spell_id)
    if unit ~= "player" or not self.interfaces_are_initialised then
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        if self:get_class_table().show_warrior_slam_cast_bar == false then
            return
        end
        local now = api.get_time()
        local live_name, live_spell_id, live_start, live_end = get_live_player_cast()
        if is_warrior_slam_token(spell_id, now) or is_warrior_slam_token(cast_guid, now)
            or is_warrior_slam_token(live_spell_id, now) or is_warrior_slam_token(live_name, now) then
            begin_warrior_slam_cast(self, live_start, live_end)
        end
        return
    end
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        end_warrior_slam_cast(self)
    end
end

-- Combat log (classic line only; main.lua registers the event for paladins and warriors
-- on non-Mainline clients and forwards the event name so this signature lines up): a
-- player attack that was dodged arms the 5 s Overpower window (reference State.lua:
-- 1315-1321 for swings and 1340-1349 for the queued melee abilities). State-only, so
-- nothing here can touch a frame. On Mainline-code clients (Retail, Forever) the event is
-- never registered, so the dodge window can never arm there; Forever arms the same
-- window through the Bloodthrill aura instead (see on_aura_change).
function ST.WARRIOR.on_combat_log_unfiltered(self, _, timestamp, event, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
    if not self.interfaces_are_initialised then
        return
    end
    if source_guid ~= self.player_guid then
        return
    end
    if event == "SWING_MISSED" then
        -- Payload after the destination flags: missType, isOffHand, amountMissed.
        if select(1, ...) == "DODGE" then
            self.warrior_overpower_proc_until = api.get_time() + WARRIOR_OVERPOWER_PROC_WINDOW
        end
        return
    end
    if event == "SPELL_MISSED" then
        -- Payload: spellId, spellName, spellSchool, missType. Only the queued melee
        -- abilities can dodge-proc Overpower (reference State.lua:1343). Anniversary
        -- (UNCONFIRMED, R1) may send the spell name where classic sends the numeric
        -- id: match the id first (the classic path, unchanged), then fall back to
        -- the localized ability names plus the literal English fallbacks. A nil id
        -- never matches, as before.
        local spell_id, spell_name = select(1, ...), select(2, ...)
        local miss_type = select(4, ...)
        local proc_match = (type(spell_id) == "number"
            and (hs_ids[spell_id] ~= nil or cleave_ids[spell_id] ~= nil))
        if not proc_match and type(spell_id) == "string"
            and type(spell_name) == "string" then
            -- String id slot: the payload carries the name twice; match either slot.
            proc_match = is_warrior_queued_melee_proc_name(spell_id, api.get_time())
                or is_warrior_queued_melee_proc_name(spell_name, api.get_time())
        end
        if miss_type == "DODGE" and proc_match then
            self.warrior_overpower_proc_until = api.get_time() + WARRIOR_OVERPOWER_PROC_WINDOW
        end
    end
end

--=========================================================================================
-- Widget construction
--=========================================================================================

-- Creates the tracker widgets on the mainhand visuals frame (called from post_init;
-- on_bar_update retries if the frame was not ready yet). Thin textures rather than
-- frames, like the shaman/druid tracker widgets.
function ST.WARRIOR.setup_warrior_visuals(self)
    local vf = self:get_visuals_frame("mainhand")
    if not vf then
        return
    end

    if not vf.warrior_shield_block then
        -- Shield Block bar: dark backing + duration fill, 4 px (reference
        -- UpdateWarriorShieldBlockBar, ClassMods.lua:2037-2144).
        local bg = vf:CreateTexture(nil, "OVERLAY")
        bg:SetDrawLayer("OVERLAY", -2)
        bg:SetColorTexture(0, 0, 0, 0.5)
        bg:SetHeight(WARRIOR_SHIELD_BLOCK_HEIGHT)
        bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, WARRIOR_BAR_BOTTOM_GAP)
        bg:Hide()

        local fill = vf:CreateTexture(nil, "OVERLAY")
        fill:SetDrawLayer("OVERLAY", -2)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetHeight(WARRIOR_SHIELD_BLOCK_HEIGHT)
        fill:SetWidth(1)
        fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        fill:Hide()

        -- Spell icon LEFT of the bar (reference ClassMods.lua:2098-2104); it is only
        -- shown once the client's spell data answered with a texture.
        local icon = vf:CreateTexture(nil, "OVERLAY")
        icon:SetSize(WARRIOR_SHIELD_BLOCK_HEIGHT, WARRIOR_SHIELD_BLOCK_HEIGHT)
        icon:SetPoint("RIGHT", bg, "LEFT", -2, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:Hide()

        vf.warrior_shield_block = { bg = bg, fill = fill, icon = icon }
    end

    if not vf.warrior_slam then
        -- Slam cast bar: dark backing + progress fill with the "SLAM X.Xs" label right
        -- of the bar (reference UpdateWarriorSlamBar, ClassMods.lua:1917-1967).
        local bg = vf:CreateTexture(nil, "OVERLAY")
        bg:SetDrawLayer("OVERLAY", -2)
        bg:SetColorTexture(0, 0, 0, 0.5)
        bg:SetHeight(WARRIOR_SLAM_HEIGHT)
        bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, WARRIOR_BAR_BOTTOM_GAP)
        bg:Hide()

        local fill = vf:CreateTexture(nil, "OVERLAY")
        fill:SetDrawLayer("OVERLAY", -2)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetHeight(WARRIOR_SLAM_HEIGHT)
        fill:SetWidth(1)
        fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        fill:Hide()

        local label = vf:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", bg, "RIGHT", 2, 0)
        label:SetJustifyH("LEFT")
        label:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
        label:SetTextColor(WARRIOR_SLAM_LABEL_COLOR[1], WARRIOR_SLAM_LABEL_COLOR[2],
            WARRIOR_SLAM_LABEL_COLOR[3], WARRIOR_SLAM_LABEL_COLOR[4])
        label:Hide()

        vf.warrior_slam = { bg = bg, fill = fill, label = label }
    end

    if not vf.warrior_debuff then
        -- Debuff bars: dark backing + fill + 1 px glow frame + centred label, one group
        -- per debuff (reference ClassMods.lua:2265-2307 etc.). All five share the
        -- geometry; the fill colour and label text are driven per frame.
        local bars = {}
        for i = 1, #warrior_debuff_defs do
            local def = warrior_debuff_defs[i]
            local bg = vf:CreateTexture(nil, "OVERLAY")
            bg:SetDrawLayer("OVERLAY", -2)
            bg:SetColorTexture(0, 0, 0, 0.45)
            bg:SetHeight(WARRIOR_DEBUFF_HEIGHT)
            bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, WARRIOR_BAR_BOTTOM_GAP)
            bg:Hide()

            local fill = vf:CreateTexture(nil, "OVERLAY")
            fill:SetDrawLayer("OVERLAY", -2)
            fill:SetColorTexture(1, 1, 1, 1)
            fill:SetHeight(WARRIOR_DEBUFF_HEIGHT)
            fill:SetWidth(1)
            fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
            fill:Hide()

            local glow = vf:CreateTexture(nil, "OVERLAY")
            glow:SetDrawLayer("OVERLAY", -3)
            glow:SetColorTexture(1, 1, 1, 1)
            glow:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -1, -1)
            glow:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 1, 1)
            glow:Hide()

            local label = vf:CreateFontString(nil, "OVERLAY")
            label:SetPoint("CENTER", bg, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
            label:SetTextColor(1.0, 0.85, 0.25, 0.95)
            label:Hide()

            bars[def.key] = { bg = bg, fill = fill, glow = glow, label = label }
        end
        vf.warrior_debuff = bars
    end

    if not vf.warrior_overpower_edges then
        -- Overpower proc flash: four 1 px gold edges around the bar plus the "OP" centre
        -- marker (reference ClassMods.lua:1974-2015). Only alpha/visibility is written
        -- per frame; the anchors are static.
        local edges = {}

        local top = vf:CreateTexture(nil, "OVERLAY")
        top:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", -1, 0)
        top:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 1, 0)
        top:SetHeight(1)
        top:SetColorTexture(WARRIOR_OP_EDGE_COLOR[1], WARRIOR_OP_EDGE_COLOR[2],
            WARRIOR_OP_EDGE_COLOR[3], 0)
        top:Hide()
        edges[#edges + 1] = top

        local bottom = vf:CreateTexture(nil, "OVERLAY")
        bottom:SetPoint("TOPLEFT", vf, "BOTTOMLEFT", -1, 0)
        bottom:SetPoint("TOPRIGHT", vf, "BOTTOMRIGHT", 1, 0)
        bottom:SetHeight(1)
        bottom:SetColorTexture(WARRIOR_OP_EDGE_COLOR[1], WARRIOR_OP_EDGE_COLOR[2],
            WARRIOR_OP_EDGE_COLOR[3], 0)
        bottom:Hide()
        edges[#edges + 1] = bottom

        local left = vf:CreateTexture(nil, "OVERLAY")
        left:SetPoint("TOPRIGHT", vf, "TOPLEFT", 0, 1)
        left:SetPoint("BOTTOMRIGHT", vf, "BOTTOMLEFT", 0, -1)
        left:SetWidth(1)
        left:SetColorTexture(WARRIOR_OP_EDGE_COLOR[1], WARRIOR_OP_EDGE_COLOR[2],
            WARRIOR_OP_EDGE_COLOR[3], 0)
        left:Hide()
        edges[#edges + 1] = left

        local right = vf:CreateTexture(nil, "OVERLAY")
        right:SetPoint("TOPLEFT", vf, "TOPRIGHT", 0, 1)
        right:SetPoint("BOTTOMLEFT", vf, "BOTTOMRIGHT", 0, -1)
        right:SetWidth(1)
        right:SetColorTexture(WARRIOR_OP_EDGE_COLOR[1], WARRIOR_OP_EDGE_COLOR[2],
            WARRIOR_OP_EDGE_COLOR[3], 0)
        right:Hide()
        edges[#edges + 1] = right

        vf.warrior_overpower_edges = edges

        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", vf, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), 12, "OUTLINE")
        text:SetTextColor(WARRIOR_OP_TEXT_COLOR[1], WARRIOR_OP_TEXT_COLOR[2],
            WARRIOR_OP_TEXT_COLOR[3], WARRIOR_OP_TEXT_COLOR[4])
        text:Hide()
        vf.warrior_overpower_text = text
    end

    if not vf.warrior_rampage_text then
        -- Rampage upkeep badge: the stack count + refresh window beside the bar's
        -- right edge (the Shamanistic Rage badge pattern in classes/shaman.lua:
        -- one FontString, text re-set only when the readout changes).
        local rampage_text = vf:CreateFontString(nil, "OVERLAY")
        rampage_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, 2)
        rampage_text:SetJustifyH("LEFT")
        rampage_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
        rampage_text:SetTextColor(self:convert_color(WARRIOR_RAMPAGE_BADGE_COLOR))
        rampage_text:Hide()
        vf.warrior_rampage_text = rampage_text
    end

    if not vf.warrior_bank then
        -- W1 rage-bank cue (buildout W1): the Overpower flash's static powerset
        -- - a 2 px amber top edge plus a centred 12 px "BANK" label. Colour and
        -- geometry are fixed at creation; the per-frame path only flips their
        -- visibility (GetTimePreciseSec-free, allocation-free).
        local edge = vf:CreateTexture(nil, "OVERLAY")
        edge:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", -1, 0)
        edge:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 1, 0)
        edge:SetHeight(2)
        edge:SetColorTexture(self:convert_color(WARRIOR_BANK_EDGE_COLOR))
        edge:Hide()

        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", vf, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), 12, "OUTLINE")
        text:SetTextColor(self:convert_color(WARRIOR_BANK_TEXT_COLOR))
        -- Static label: the per-frame path only flips visibility, so the text
        -- is written once here and never re-set on the draw path.
        text:SetText("BANK")
        text:Hide()

        vf.warrior_bank = { edge = edge, text = text }
    end

    if not vf.warrior_battle_shout_text then
        -- Battle Shout uptime badge (buildout - the Rampage badge pattern one
        -- widget above the rampage text; same font, same right-edge anchor).
        local battle_shout_text = vf:CreateFontString(nil, "OVERLAY")
        battle_shout_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, 16)
        battle_shout_text:SetJustifyH("LEFT")
        battle_shout_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
        battle_shout_text:SetTextColor(self:convert_color(WARRIOR_BATTLE_SHOUT_BADGE_COLOR))
        battle_shout_text:Hide()
        vf.warrior_battle_shout_text = battle_shout_text
    end
end

--=========================================================================================
-- Per-frame drawing
--=========================================================================================

-- Cached restack (reference RestackDebuffBars, ClassMods.lua:125-181): a bar only
-- re-issues its anchors when the slot it should occupy actually moves, so the per-frame
-- path never churns layout while nothing changes.
local function place_warrior_bar(bar, vf, stack_y)
    if bar.stack_y ~= stack_y then
        bar.stack_y = stack_y
        bar.bg:ClearAllPoints()
        bar.bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, stack_y)
        bar.bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, stack_y)
    end
end

-- Shield Block bar: 4 px with the buff's remaining time and its icon, slot 0 of the
-- shared stack; hidden while the aura is absent (reference ClassMods.lua:2037-2144).
local function update_warrior_shield_block(self, vf, db, now, w, stack_y)
    local bar = vf.warrior_shield_block
    local duration = self.warrior_shield_block_duration
    local expiration = self.warrior_shield_block_expires
    local remaining
    if type(duration) == "number" and duration > 0
        and type(expiration) == "number" and expiration > 0 then
        remaining = expiration - now
        if remaining < 0 then
            remaining = 0
        end
    end
    if db.show_warrior_shield_block_bar == false or remaining == nil then
        bar.bg:Hide()
        bar.fill:Hide()
        bar.icon:Hide()
        return stack_y
    end
    if type(w) == "number" and w > 0 then
        local fraction = remaining / duration
        if fraction < 0 then
            fraction = 0
        elseif fraction > 1 then
            fraction = 1
        end
        bar.fill:SetWidth(w * fraction)
    end
    local colour = db.warrior_shield_block_bar_color or WARRIOR_SHIELD_BLOCK_FALLBACK_COLOR
    if bar.color_applied ~= colour then
        bar.color_applied = colour
        bar.fill:SetVertexColor(self:convert_color(colour))
    end
    if shield_block_icon_resolved and bar.icon_path ~= shield_block_icon_resolved then
        bar.icon_path = shield_block_icon_resolved
        bar.icon:SetTexture(shield_block_icon_resolved)
    end
    place_warrior_bar(bar, vf, stack_y)
    bar.bg:Show()
    bar.fill:Show()
    if shield_block_icon_resolved then
        bar.icon:Show()
    end
    return stack_y + WARRIOR_SHIELD_BLOCK_HEIGHT + WARRIOR_BAR_STACK_GAP
end

-- Slam cast bar: cast progress with the "SLAM X.Xs" remaining label, slot 1 of the
-- shared stack (reference ClassMods.lua:1917-1967). The fill grows with the cast like the
-- hunter cast bar; the label only re-formats when its tenth-of-a-second readout changes,
-- so the per-frame path allocates nothing.
local function update_warrior_slam(self, vf, db, now, w, stack_y)
    local bar = vf.warrior_slam
    local start_time = self.warrior_slam_cast_start
    local duration = self.warrior_slam_cast_duration
    if db.show_warrior_slam_cast_bar == false
        or not self.warrior_slam_casting
        or type(start_time) ~= "number"
        or type(duration) ~= "number" or duration <= 0 then
        bar.bg:Hide()
        bar.fill:Hide()
        bar.label:Hide()
        return stack_y
    end
    local elapsed = now - start_time
    if elapsed < 0 then
        elapsed = 0
    elseif elapsed > duration then
        elapsed = duration
    end
    if type(w) == "number" and w > 0 then
        bar.fill:SetWidth(math.max(1, w * elapsed / duration))
    end
    -- Slam safe-window band (brainstorm W4): green when the cast lands before
    -- the next swing, red when the swing lands mid-cast. The verdict is the
    -- pure st.warrior_guide.slam_cast_safety helper (guarded: a flavor without
    -- that module keeps the white fill); without swing data the fill is left
    -- alone. The colour is only re-applied on a verdict change, like the
    -- cached restack above.
    local guide = st.warrior_guide
    if guide and guide.slam_cast_safety then
        local swing_remaining
        if self.mainhand and type(self.mainhand.ends_at) == "number" then
            swing_remaining = self.mainhand.ends_at - now
        end
        local safety = guide.slam_cast_safety(duration - elapsed, swing_remaining,
            st.family ~= "FOREVER")
        local colour
        if safety == "clean" then
            colour = WARRIOR_SLAM_SAFE_COLOR
        elseif safety == "clash" then
            colour = WARRIOR_SLAM_CLASH_COLOR
        end
        if colour and bar.safety_applied ~= colour then
            bar.safety_applied = colour
            bar.fill:SetVertexColor(self:convert_color(colour))
        elseif colour == nil then
            bar.safety_applied = nil
        end
    end
    local remaining = duration - elapsed
    local tenths = math.floor(remaining * 10 + 0.5)
    if bar.label_tenths ~= tenths then
        bar.label_tenths = tenths
        bar.label:SetText(string.format("SLAM %.1fs", remaining))
    end
    place_warrior_bar(bar, vf, stack_y)
    bar.bg:Show()
    bar.fill:Show()
    bar.label:Show()
    return stack_y + WARRIOR_SLAM_HEIGHT + WARRIOR_BAR_STACK_GAP
end

-- Debuff bars: the throttled scan above feeds all five; between scans each bar just
-- counts down. Whole-second label (Sunder Armor shows its stack count instead), a glow
-- frame inside the final 4 s and the configured fill colour, stacked bottom-to-top in the
-- reference's restack order with the cached restack above.
local function update_warrior_debuff_bars(self, vf, db, now, w, stack_y)
    local bars = vf.warrior_debuff
    if not bars then
        return stack_y
    end
    for i = 1, #warrior_debuff_defs do
        local def = warrior_debuff_defs[i]
        local bar = bars[def.key]
        if db[def.option] == false or warrior_debuff_found[def.key] ~= true then
            bar.glow_on = nil
            bar.bg:Hide()
            bar.fill:Hide()
            bar.glow:Hide()
            bar.label:Hide()
        else
            local remaining, total = self.WARRIOR.get_debuff_remaining(
                warrior_debuff_duration[def.key], warrior_debuff_expiration[def.key],
                now, def.fallback_duration)
            if type(w) == "number" and w > 0 and total > 0 then
                local fraction = remaining / total
                if fraction < 0 then
                    fraction = 0
                elseif fraction > 1 then
                    fraction = 1
                end
                bar.fill:SetWidth(w * fraction)
            end
            local colour = db[def.color_option] or def.fallback_color
            if bar.color_applied ~= colour then
                bar.color_applied = colour
                bar.fill:SetVertexColor(self:convert_color(colour))
                bar.glow:SetVertexColor(self:convert_color(colour))
            end
            local label_value
            if def.label_mode == "stacks" then
                label_value = warrior_debuff_stacks[def.key] or 1
            else
                label_value = math.floor(remaining + 0.5)
            end
            if bar.label_value ~= label_value then
                bar.label_value = label_value
                bar.label:SetText(tostring(label_value))
            end
            local glow_on = self.WARRIOR.should_debuff_glow(remaining)
            if glow_on ~= bar.glow_on then
                bar.glow_on = glow_on
                if glow_on then
                    bar.glow:Show()
                else
                    bar.glow:Hide()
                end
            end
            place_warrior_bar(bar, vf, stack_y)
            bar.bg:Show()
            bar.fill:Show()
            bar.label:Show()
            stack_y = stack_y + WARRIOR_DEBUFF_HEIGHT + WARRIOR_BAR_STACK_GAP
        end
    end
    return stack_y
end

-- Overpower proc flash: a pulsing 1 px gold border around the bar plus the "OP" centre
-- marker while the dodge window is live (reference UpdateWarriorOverpowerFlash,
-- ClassMods.lua:1969-2035). The pulse alpha is written per frame like the reference;
-- the classic dodge window can only be armed through the combat log, so Retail
-- never shows this; Forever arms the same window through the Bloodthrill aura.
local function update_warrior_overpower_flash(self, vf, db, now)
    local edges = vf.warrior_overpower_edges
    local text = vf.warrior_overpower_text
    if not (edges and text) then
        return
    end
    local remaining = self.WARRIOR.get_overpower_remaining(self.warrior_overpower_proc_until, now)
    if db.show_warrior_overpower_flash == false or remaining == nil then
        if self.warrior_overpower_flash_on then
            self.warrior_overpower_flash_on = false
            for i = 1, #edges do
                edges[i]:Hide()
            end
            text:Hide()
        end
        return
    end
    if not self.warrior_overpower_flash_on then
        self.warrior_overpower_flash_on = true
        text:SetText("OP")
        text:Show()
    end
    local pulse = 0.5 + (0.5 * math.sin(now * WARRIOR_OP_PULSE_HZ))
    local alpha = 0.25 + (0.45 * pulse)
    for i = 1, #edges do
        edges[i]:SetColorTexture(WARRIOR_OP_EDGE_COLOR[1], WARRIOR_OP_EDGE_COLOR[2],
            WARRIOR_OP_EDGE_COLOR[3], alpha)
        edges[i]:Show()
    end
end

-- One throttled read pass (0.05 s) feeds the merged target scan and the player Shield
-- Block read; each scan only runs while at least one option that consumes it is on, so an
-- all-off configuration performs no aura reads at all. The bars then restack through the
-- shared slot walk: Shield Block (closest to the bar), Slam, then the five debuff bars in
-- the reference's restack order.
local function update_warrior_bars(self, vf, db, now, w)
    local any_debuff = false
    for i = 1, #warrior_debuff_defs do
        if db[warrior_debuff_defs[i].option] ~= false then
            any_debuff = true
            break
        end
    end
    local shield_block_on = db.show_warrior_shield_block_bar ~= false
    if (any_debuff or shield_block_on) and now >= (self.warrior_scan_at or 0) then
        self.warrior_scan_at = now + WARRIOR_SCAN_INTERVAL
        if any_debuff then
            scan_target_warrior_debuffs(now)
        end
        if shield_block_on then
            local duration, expiration = scan_player_shield_block(now)
            self.warrior_shield_block_duration = duration
            self.warrior_shield_block_expires = expiration
        else
            self.warrior_shield_block_duration = nil
            self.warrior_shield_block_expires = nil
        end
    end
    local stack_y = WARRIOR_BAR_BOTTOM_GAP
    stack_y = update_warrior_shield_block(self, vf, db, now, w, stack_y)
    stack_y = update_warrior_slam(self, vf, db, now, w, stack_y)
    update_warrior_debuff_bars(self, vf, db, now, w, stack_y)
end

-- Rampage upkeep badge: the stack count + refresh window beside the bar's right
-- edge (the Shamanistic Rage badge pattern in classes/shaman.lua). The aura scan
-- in on_aura_change owns the state, so this performs no client reads and stays
-- cheap: hidden while the buff is absent or elapsed, and the text is only re-set
-- when the readout actually changes. Default-on like the other trackers (the
-- option key reads nil until a config lane ships its default); an explicit false
-- hides the badge. Family-agnostic on purpose: a client without the buff never
-- shows it, so no family gate is needed (and Retail stays inert).
local function update_warrior_rampage_badge(self, vf, db, now)
    local badge = vf.warrior_rampage_text
    if not badge then
        return
    end
    if db.show_warrior_rampage_badge == false then
        self.warrior_rampage_text_shown = nil
        badge:Hide()
        return
    end
    local text = self.WARRIOR.get_rampage_display(
        self.warrior_rampage_stacks, self.warrior_rampage_expires, now)
    if text == nil then
        self.warrior_rampage_text_shown = nil
        badge:Hide()
        return
    end
    if self.warrior_rampage_text_shown ~= text then
        self.warrior_rampage_text_shown = text
        badge:SetText(text)
    end
    -- W3 tier colours: the badge recolours only on a tier change (the text
    -- re-set above is unaffected by it). tier is never nil on this path (a
    -- live badge always has stacks), so the lookup below always resolves.
    local tier = self.WARRIOR.get_rampage_tier(
        self.warrior_rampage_stacks, self.warrior_rampage_expires, now)
    if tier ~= self.warrior_rampage_tier_applied then
        self.warrior_rampage_tier_applied = tier
        badge:SetTextColor(self:convert_color(WARRIOR_RAMPAGE_TIER_COLORS[tier]))
    end
    badge:Show()
end

-- W1 rage-bank cue (verify W1): the amber top edge + centred "BANK" while the
-- bank state holds in combat. Default OFF (show_warrior_bank_cue ~= true: nil
-- stays off like every other new toggle) and every client read sits behind the
-- toggle, so an all-off configuration reads nothing. Visibility only flips on
-- a transition; no per-frame colour or text write.
local function update_warrior_bank_cue(self, vf, db, now)
    local widgets = vf.warrior_bank
    if not widgets then
        return
    end
    if db.show_warrior_bank_cue ~= true then
        self.warrior_bank_shown = false
        widgets.edge:Hide()
        widgets.text:Hide()
        return
    end
    -- Player reads behind the toggle: an unreadable percentage never arms the
    -- state (see get_bank_state). Rage is the warrior's primary power read.
    local health_max = api.UnitHealthMax("player")
    local health = api.UnitHealth("player")
    local health_pct
    if type(health_max) == "number" and health_max > 0 and type(health) == "number" then
        health_pct = health / health_max * 100
    end
    local show = ST.WARRIOR.get_bank_state(health_pct, db.guide_execute_pct or 20,
        api.UnitPower("player"), self.in_combat) == true
    if show then
        self.warrior_bank_shown = true
        widgets.edge:Show()
        widgets.text:Show()
    else
        self.warrior_bank_shown = false
        widgets.edge:Hide()
        widgets.text:Hide()
    end
end

-- Battle Shout uptime badge: the "BS xxs" count-down beside the bar's right
-- edge, one widget above the rampage text. Default OFF
-- (show_warrior_battle_shout_badge ~= true: nil stays off). The capture rides
-- the aura walk regardless (it adds no client read); this toggles only the
-- drawing. Deliberately NOT cleared in on_combat_exit.
local function update_warrior_battle_shout_badge(self, vf, db, now)
    local badge = vf.warrior_battle_shout_text
    if not badge then
        return
    end
    if db.show_warrior_battle_shout_badge ~= true then
        self.warrior_battle_shout_text_shown = nil
        badge:Hide()
        return
    end
    local text = self.WARRIOR.get_battle_shout_display(
        self.warrior_battle_shout_expires, now)
    if text == nil then
        self.warrior_battle_shout_text_shown = nil
        badge:Hide()
        return
    end
    if self.warrior_battle_shout_text_shown ~= text then
        self.warrior_battle_shout_text_shown = text
        badge:SetText(text)
    end
    badge:Show()
end

-- Per-frame warrior visuals, called from ST:onupdate_common via the generic class hook.
-- The mainhand frame's OnUpdate only ticks while the bar is shown, so the widgets freeze
-- with the bar. Deliberately cheap and nil-safe: no LibStub calls, no allocations. NOTE:
-- deliberately not gated on st.is_mainline - the Forever client is Mainline-code but
-- shows all of this; the Overpower flash stays inert there because nothing can arm it.
function ST.WARRIOR.on_bar_update(self, hand)
    if hand ~= "mainhand" then
        return
    end
    -- Next Action Guide (mainhand only): driven before the tracker gates below so it
    -- also runs where the tracker widgets are missing. Deliberately not gated on
    -- st.is_mainline - the Forever client is Mainline-code but shows the guide; swing
    -- activity decides instead (the Retail stand-in never reports a swing). Settings
    -- that rebuild the frame (scale/position/lock) are applied when the class options
    -- change; the display toggles are read live by the UI.
    local db = self:get_class_table()
    if db.nextaction_icon_size ~= self.guide_ui_icon_size
        or db.nextaction_x ~= self.guide_ui_x
        or db.nextaction_y ~= self.guide_ui_y
        or db.nextaction_locked ~= self.guide_ui_locked then
        self.guide_ui_icon_size = db.nextaction_icon_size
        self.guide_ui_x = db.nextaction_x
        self.guide_ui_y = db.nextaction_y
        self.guide_ui_locked = db.nextaction_locked
        if st.nextaction_ui then
            st.nextaction_ui.apply_settings(self)
        end
    end
    if st.nextaction_ui then
        st.nextaction_ui.on_bar_update(self, hand)
    end
    -- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
    -- changes up between the HUD driver's ticks (the row itself ticks on its own
    -- driver frame, so this is cheap). Deliberately not gated on st.is_mainline:
    -- the Forever client must show the HUD, and the Retail stand-in simply never
    -- swings (the paladin hooks it the same way in classes/paladin.lua).
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    local vf = self:get_visuals_frame(hand)
    if not vf then
        return
    end
    if not vf.warrior_debuff then
        self.WARRIOR.setup_warrior_visuals(self)
        if not vf.warrior_debuff then
            return
        end
    end
    local now = api.get_time()
    local w = self:get_bar_visuals_width_and_height(hand)
    update_warrior_overpower_flash(self, vf, db, now)
    update_warrior_bars(self, vf, db, now, w)
    update_warrior_rampage_badge(self, vf, db, now)
    -- Build-out round 1: the W1 bank cue and the Battle Shout badge below the
    -- rampage call, in the same draw pass (visibility-only churn for the cue).
    update_warrior_bank_cue(self, vf, db, now)
    update_warrior_battle_shout_badge(self, vf, db, now)
end

--=========================================================================================
-- Next Action Guide: the warrior provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision model is the pure st.warrior_guide module (warrior_guide.lua; its
-- docblock is the frozen spec), the live reads live in gather_guide_inputs, and this
-- table is the last piece of glue: the slot set, the gather/evaluate pair and the static
-- captions. Default OFF (nextaction_enabled=false in config_presets.lua): a wrong prompt
-- is worse than none, so the owner enables it after in-client verification.
--
-- FIVE slots (op, execute, slam, hs, cleave - the contract allows six). Every slot
-- carries a cooldown_key: the swipe follows the ability's own client-reported cooldown
-- where one exists (the gather's GCD-echo rule keeps a running GCD out of it). On the
-- classic families these abilities mostly have no cooldown of their own, so the swipes
-- typically stay clear; the inputs still ride the frozen name set in full.
--
-- TBC fury (st.family == "TBC") swaps in a six-slot set at the contract maximum:
-- op, execute, slam, hs, bt, ww. The cleave slot is the one replaced: no rule ever
-- outputs "cleave" (the slot only ever showed the Cleave swipe, and Cleave has no
-- cooldown of its own on the classic line), while Bloodthirst and Whirlwind are the
-- TBC core. The cleave readers stay in the gather (cost/queue/cooldown), so the
-- queued-Cleave RIDE path is unchanged and a future slot re-add needs no new reads.
--
-- Era fury (st.family == "ERA") uses the same six-slot shape (op, execute, slam,
-- hs, bt, ww): BT/WW are vanilla spells that exist on Era. Same replacement,
-- same reader retention. SoD (ERA + SoD runes, frozen at post_init) swaps in
-- execute, slam, hs, bt, ww, raging_blow: Overpower is the least-SoD-relevant
-- slot (unlisted in the SoD priority; its dodge-window/cooldown readers stay
-- for a future re-add) and Raging Blow is the rune filler after WW.
--
-- Wrath fury (st.family == "WRATH", no Mortal Strike known) uses the same six
-- keys as TBC/Era (op, execute, slam, hs, bt, ww): the fury priority names
-- exactly these and the conditional Rend stays tracker-only. Wrath arms
-- (Mortal Strike known) swaps in op, execute, rend, ms, bladestorm, hs:
-- BT/WW/Cleave carry no arms rule and Slam is the deferred early-tier filler
-- (its readers stay, its rule stays off, HS covers the filler window), while
-- Rend upkeep, Mortal Strike and Bladestorm take their places. Both Wrath sets
-- and the SoD set are picked at post_init from the frozen spec/rune probe (see
-- resolve_guide_slots); a respec or rune change needs /reload.
--
-- Forever (st.family == "FOREVER") keeps the base five-slot set: Victory Rush
-- reuses the execute slot (the engine's victory_rush bypass names "execute",
-- so no sixth slot is needed) and Bloodthrill reuses the OP dodge-window
-- reader (it arms the same window). The contract stays full but unchanged.
--
-- Rampage (TBC fury "stack to 5 then upkeep"): tracked as the upkeep badge above
-- (stack count + refresh window). The stack count is plumbed through
-- on_aura_change (a second aura id alongside Blood Surge) into
-- warrior_rampage_stacks / warrior_rampage_expires; the badge shows it while
-- the buff is live. No guide rule and no display slot: the six-contract has no
-- room (see the slot note above), so the guide never prompts Rampage.
-- Plug-in point for a future rule: new rampage_stacks gather inputs in
-- gather_guide_inputs below, a rule above Bloodthirst, and a seventh slot the
-- contract does not have.

-- One reused input table: no per-frame allocations on the guide tick (the frame passes
-- its own reused table through gather; this one serves direct calls).
ST.WARRIOR.guide_inputs = {}

-- The current Slam / Mortal Strike / Rend ranks for the guide (resolved once,
-- like the HS/Cleave caches).
local slam_current_id
local ms_current_id
local rend_current_id

-- Live cooldown for the guide, with the client's GCD echo filtered: GetSpellCooldown
-- reports whichever cooldown ends later, so a reading of 1.51 s or less is a GCD echo
-- and never one of these abilities' own cooldowns. Returns remaining seconds (>= 0) and
-- the client-reported duration, or (0, nil) when there is no real cooldown to show.
local function get_guide_cooldown(spell)
    if not spell then
        return 0, nil
    end
    local start_time, duration = api.GetSpellCooldown(spell)
    if not start_time or not duration or duration <= 1.51 then
        return 0, nil
    end
    local remaining = start_time + duration - api.get_time()
    if remaining <= 0 then
        return 0, nil
    end
    return remaining, duration
end

-- Slot descriptors: the rank-1 ids ship as the fallback; resolve_guide_icons re-points
-- slam / hs / cleave at the client's current rank once the spell data is live. Overpower
-- keeps 7384 (the id the rest of the module's matcher uses) and Execute keeps the spec's
-- 5308; neither has a cooldown of its own on the target families, so their cooldown and
-- swipe reads simply stay clear there. swipe_duration is the display fallback for a
-- swipe whose length the client never reported.
local guide_slot_op = { key = "op", spell_id = overpower_id, cooldown_key = "op",
    swipe_duration = 1.5 }
local guide_slot_execute = { key = "execute", spell_id = 5308, cooldown_key = "execute",
    swipe_duration = 1.5 }
local guide_slot_slam = { key = "slam", spell_id = 1464, cooldown_key = "slam",
    swipe_duration = 1.5 }
local guide_slot_hs = { key = "hs", spell_id = 78, cooldown_key = "hs",
    swipe_duration = 1.5 }
local guide_slot_cleave = { key = "cleave", spell_id = 845, cooldown_key = "cleave",
    swipe_duration = 1.5 }
local guide_slot_bt = { key = "bt", spell_id = 23881, cooldown_key = "bt",
    swipe_duration = 1.5 }
local guide_slot_ww = { key = "ww", spell_id = 1680, cooldown_key = "ww",
    swipe_duration = 1.5 }
-- Arms / SoD slots: Rend (rank-1 fallback 772, re-pointed like slam; its swipe
-- follows the debuff window the gather feeds, not a cooldown), Mortal Strike
-- (rank-1 fallback 12294, re-pointed through ms_ids), Bladestorm (63784; the 90 s
-- swipe fallback NEEDS IN-CLIENT CONFIRMATION) and Raging Blow (402911; 8 s).
local guide_slot_rend = { key = "rend", spell_id = 772, cooldown_key = "rend",
    swipe_duration = 1.5 }
local guide_slot_ms = { key = "ms", spell_id = 12294, cooldown_key = "ms",
    swipe_duration = 6 }
local guide_slot_bladestorm = { key = "bladestorm", spell_id = bladestorm_id,
    cooldown_key = "bladestorm", swipe_duration = 90 }
local guide_slot_raging = { key = "raging_blow", spell_id = raging_blow_id,
    cooldown_key = "raging_blow", swipe_duration = 8 }

-- The slot set is picked once at load: the TBC fury set on the TBC family, the
-- Era fury set (same six keys, shared slot objects) on the ERA family, the
-- Wrath fury set (same six keys again) on the WRATH family, the frozen
-- five-slot set everywhere else (untouched, including Retail/Forever).
-- post_init re-picks through resolve_guide_slots (arms / SoD shapes) once the
-- spell data and the spec/rune probes answer.
local guide_slots_base = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_cleave }
local guide_slots_tbc = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww }
local guide_slots_era = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww }
local guide_slots_wrath_fury = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww }
local guide_slots_wrath_arms = { guide_slot_op, guide_slot_execute, guide_slot_rend,
    guide_slot_ms, guide_slot_bladestorm, guide_slot_hs }
local guide_slots_sod = { guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww, guide_slot_raging }

-- Resolve the guide icons to the client's current ranks; called once from post_init,
-- before the shared frame builds its icons. A rank that does not resolve keeps the
-- rank-1 fallback above.
function ST.WARRIOR.resolve_guide_icons()
    hs_current_id = resolve_rank(hs_ids, hs_current_id)
    cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
    slam_current_id = resolve_rank(slam_ids, slam_current_id)
    bt_current_id = resolve_rank(bt_ids, bt_current_id)
    ww_current_id = resolve_rank(ww_ids, ww_current_id)
    ms_current_id = resolve_rank(ms_ids, ms_current_id)
    rend_current_id = resolve_rank(rend_ids, rend_current_id)
    if hs_current_id then
        guide_slot_hs.spell_id = hs_current_id
    end
    if cleave_current_id then
        guide_slot_cleave.spell_id = cleave_current_id
    end
    if slam_current_id then
        guide_slot_slam.spell_id = slam_current_id
    end
    if bt_current_id then
        guide_slot_bt.spell_id = bt_current_id
    end
    if ww_current_id then
        guide_slot_ww.spell_id = ww_current_id
    end
    if ms_current_id then
        guide_slot_ms.spell_id = ms_current_id
    end
    if rend_current_id then
        guide_slot_rend.spell_id = rend_current_id
    end
end

-- Rend debuff window for the arms upkeep (target scan, arms only, so every other
-- branch pays no aura reads here). Matches by rank id, the client's localized
-- names, then the literal English fallback; the aura must belong to the
-- player. Returns remaining, duration - nil when missing/unknown, which prompts
-- (the druid rip/rake nil rule). The 15 s fallback is the wotlk Rend duration
-- (wowhead.com/wotlk/spell=47465).
local function get_rend_debuff_window(now)
    local localized = nil
    local index = 1
    while index <= 40 do
        local name, _, _, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("target", index, "HARMFUL")
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it.
        if name ~= nil then
            if source == "player" or source == nil then
                local match = (type(spell_id) == "number" and rend_ids[spell_id] ~= nil)
                    or name == "Rend"
                if not match then
                    if localized == nil then
                        localized = {}
                        for id in pairs(rend_ids) do
                            local resolved = api.GetSpellInfo(id)
                            if resolved then
                                localized[resolved] = true
                            end
                        end
                    end
                    match = localized[name] == true
                end
                if match then
                    return ST.WARRIOR.get_debuff_remaining(
                        aura_duration, aura_expiration, now, 15)
                end
            end
        end
        index = index + 1
    end
    return nil, nil
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".
function ST.WARRIOR.gather_guide_inputs(self, out)
    local inputs = out or ST.WARRIOR.guide_inputs
    local now = api.get_time()
    local d = self.mainhand
    local gcd = self.gcd
    local db = self:get_class_table()

    -- Swing and GCD, in the api.get_time() domain (ends_at and the GCD stamp share it).
    inputs.speed = (d and d.speed) or 0
    inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
    inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0

    -- Rage, the on-next-attack state and the tracker state the rule matrix consumes.
    inputs.rage = api.UnitPower("player")
    inputs.hs_queued = self.hs_queued and true or false
    inputs.cleave_queued = self.cleave_queued and true or false
    inputs.insufficient_rage = self.insufficient_rage and true or false
    inputs.has_bloodsurge = self.has_bloodsurge and true or false
    inputs.slam_casting = self.warrior_slam_casting and true or false
    inputs.overpower_remaining = self.WARRIOR.get_overpower_remaining(
        self.warrior_overpower_proc_until, now)

    -- Target health percentage; nil = unknown (no target, a dead unit, or a client that
    -- does not answer the health reads).
    inputs.target_health_pct = nil
    local health_max = api.UnitHealthMax("target")
    if type(health_max) == "number" and health_max > 0 then
        local health = api.UnitHealth("target")
        if type(health) == "number" then
            inputs.target_health_pct = health / health_max * 100
        end
    end

    -- Rage costs of the on-next-attack abilities through the client's own current ranks
    -- (the rank caches make this a lookup once resolved; a nil cost means the client
    -- cannot answer, and the engine withholds the HS prompt).
    hs_current_id = resolve_rank(hs_ids, hs_current_id)
    cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
    local costs = hs_current_id and api.GetSpellPowerCost(hs_current_id)
    inputs.hs_cost = rage_cost_of(costs)
    costs = cleave_current_id and api.GetSpellPowerCost(cleave_current_id)
    inputs.cleave_cost = rage_cost_of(costs)

    -- Cooldowns, GCD echo filtered (op/execute feed the rule matrix, the rest feed the
    -- slot swipes). Both halves of every pair are written every call.
    inputs.op_remaining, inputs.op_duration = get_guide_cooldown(overpower_id)
    inputs.execute_remaining, inputs.execute_duration = get_guide_cooldown(5308)
    slam_current_id = resolve_rank(slam_ids, slam_current_id)
    inputs.slam_remaining, inputs.slam_duration = get_guide_cooldown(slam_current_id)
    inputs.hs_remaining, inputs.hs_duration = get_guide_cooldown(hs_current_id)
    inputs.cleave_remaining, inputs.cleave_duration = get_guide_cooldown(cleave_current_id)

    -- TBC fury core: Bloodthirst/Whirlwind cooldowns+costs and the HS dump floor.
    -- Nil on every other family (no reader there), so the new engine rules - which
    -- require known readings - stay inert outside TBC. Every field is written on
    -- every call, so no stale value can survive between ticks.
    -- Era feeds the same BT/WW readers (vanilla spells) with its own floor (30),
    -- window (2.5 s) and Execute-spam flag; every other family feeds nil for all
    -- of these, keeping the legacy behaviour and Retail inertness exactly.
    if is_tbc_guide then
        bt_current_id = resolve_rank(bt_ids, bt_current_id)
        ww_current_id = resolve_rank(ww_ids, ww_current_id)
        costs = bt_current_id and api.GetSpellPowerCost(bt_current_id)
        inputs.bt_cost = rage_cost_of(costs)
        costs = ww_current_id and api.GetSpellPowerCost(ww_current_id)
        inputs.ww_cost = rage_cost_of(costs)
        inputs.bt_remaining, inputs.bt_duration = get_guide_cooldown(bt_current_id)
        inputs.ww_remaining, inputs.ww_duration = get_guide_cooldown(ww_current_id)
        -- TBC fury rage management: Heroic Strike dumps only with rage to spare
        -- (50+), so Bloodthirst (30 rage) / Whirlwind (25 rage) are never starved.
        -- The HS-cancel cue is armed here too: cancel a queued Heroic
        -- Strike/Cleave before Execute (don't spend the 15 rage). Nil on every
        -- other family (see below), so the engine keeps its legacy shape there.
        inputs.hs_rage_floor = 50
        inputs.core_reserve_window = nil
        inputs.execute_spam = nil
        inputs.hs_cancel_cue = true
    elseif is_era_guide then
        bt_current_id = resolve_rank(bt_ids, bt_current_id)
        ww_current_id = resolve_rank(ww_ids, ww_current_id)
        costs = bt_current_id and api.GetSpellPowerCost(bt_current_id)
        inputs.bt_cost = rage_cost_of(costs)
        costs = ww_current_id and api.GetSpellPowerCost(ww_current_id)
        inputs.ww_cost = rage_cost_of(costs)
        inputs.bt_remaining, inputs.bt_duration = get_guide_cooldown(bt_current_id)
        inputs.ww_remaining, inputs.ww_duration = get_guide_cooldown(ww_current_id)
        -- Era fury rage management: Heroic Strike dumps only with rage to spare
        -- (30+) and 2-3 s until next BT/WW (2.5 s buffer), so Bloodthirst
        -- (30 rage) / Whirlwind (25 rage) are never starved; Execute spams
        -- below 20 % with no reservation against the core (unlike TBC).
        -- SoD (frozen rune probe) replaces the 30 floor with 60: Consumed by
        -- Rage pooling outranks the dump. Window and spam carry over (2.5 s,
        -- spam - in-game to confirm the SoD window).
        inputs.hs_rage_floor = ERA_HS_FLOOR
        if self.warrior_is_sod == true then
            inputs.hs_rage_floor = 60
        end
        inputs.core_reserve_window = ERA_CORE_RESERVE_WINDOW
        inputs.execute_spam = true
        inputs.hs_cancel_cue = nil
    elseif is_wrath_guide then
        if self.warrior_is_arms == true then
            -- Arms runs no BT/WW core: the readers stay nil so the HS dump
            -- never reserves against abilities arms never casts (the upkeep /
            -- cooldown readers live in the shared tail below).
            inputs.bt_cost = nil
            inputs.ww_cost = nil
            inputs.bt_remaining = nil
            inputs.bt_duration = nil
            inputs.ww_remaining = nil
            inputs.ww_duration = nil
        else
            bt_current_id = resolve_rank(bt_ids, bt_current_id)
            ww_current_id = resolve_rank(ww_ids, ww_current_id)
            costs = bt_current_id and api.GetSpellPowerCost(bt_current_id)
            inputs.bt_cost = rage_cost_of(costs)
            costs = ww_current_id and api.GetSpellPowerCost(ww_current_id)
            inputs.ww_cost = rage_cost_of(costs)
            inputs.bt_remaining, inputs.bt_duration = get_guide_cooldown(bt_current_id)
            inputs.ww_remaining, inputs.ww_duration = get_guide_cooldown(ww_current_id)
        end
        -- Wrath rage management (both specs): Heroic Strike dumps only with rage
        -- to spare (50+, TBC-carried until in-client tuning). The reserve window
        -- stays the 1.5 s engine default (nil); Execute never spams against the
        -- core on fury (nil - rule F demotes it instead) and needs no
        -- reservation on arms (nil - arms runs no core).
        inputs.hs_rage_floor = 50
        inputs.core_reserve_window = nil
        inputs.execute_spam = nil
        inputs.hs_cancel_cue = nil
    else
        inputs.bt_cost = nil
        inputs.ww_cost = nil
        inputs.bt_remaining = nil
        inputs.bt_duration = nil
        inputs.ww_remaining = nil
        inputs.ww_duration = nil
        inputs.hs_rage_floor = nil
        inputs.core_reserve_window = nil
        inputs.execute_spam = nil
        inputs.hs_cancel_cue = nil
    end

    -- Forever Victory Rush (UNCONFIRMED id + name): id-known or name-known
    -- and currently usable reads as ready (the window after a killing blow),
    -- feeding the engine's victory_rush Execute bypass. Nil on every other
    -- family and whenever neither probe answers, so the bypass stays inert
    -- there exactly like before. Written on every call, like every other
    -- frozen input.
    inputs.victory_rush = nil
    if is_forever_guide then
        local vr_known = api.is_spell_known(WARRIOR_VICTORY_RUSH_SPELL_ID)
            or type(api.GetSpellInfo(WARRIOR_VICTORY_RUSH_NAME)) == "string"
        if vr_known then
            local vr_name = api.GetSpellInfo(WARRIOR_VICTORY_RUSH_SPELL_ID)
                or WARRIOR_VICTORY_RUSH_NAME
            local ok, usable = pcall(api.IsSpellUsable, vr_name)
            if ok and usable == true then
                inputs.victory_rush = true
            end
        end
    end

    -- Execute threshold from the options (5-35 %, default 20).
    inputs.execute_pct = db.guide_execute_pct or 20

    -- Wrath / SoD branch tail: every field below is written on every call on
    -- every family (nil where the branch does not apply), so no stale value can
    -- survive between ticks and legacy families keep their exact shape plus
    -- nils. The flags freeze with the slots at post_init (see
    -- resolve_guide_slots), so the engine can never name an undeclared slot.
    local frozen_arms = is_wrath_guide and self.warrior_is_arms == true
    local frozen_sod = self.warrior_is_sod == true
    if frozen_arms then
        inputs.wrath_arms = true
    else
        inputs.wrath_arms = nil
    end
    if is_wrath_guide and not frozen_arms then
        inputs.wrath_fury = true
    else
        inputs.wrath_fury = nil
    end
    if frozen_sod then
        inputs.sod = true
    else
        inputs.sod = nil
    end
    inputs.sudden_death = self.has_sudden_death and true or nil
    inputs.tfb = self.has_tfb and true or nil

    -- Arms upkeep + cooldown readers (nil everywhere else). Rend is a target
    -- scan, arms only, so every other branch pays no aura reads here.
    if inputs.wrath_arms then
        inputs.rend_remaining, inputs.rend_duration =
            get_rend_debuff_window(now)
        ms_current_id = resolve_rank(ms_ids, ms_current_id)
        inputs.ms_remaining, inputs.ms_duration = get_guide_cooldown(ms_current_id)
        inputs.bladestorm_remaining, inputs.bladestorm_duration =
            get_guide_cooldown(bladestorm_id)
        inputs.bladestorm_known = api.is_spell_known(bladestorm_id) or nil
    else
        inputs.rend_remaining, inputs.rend_duration = nil, nil
        inputs.ms_remaining, inputs.ms_duration = nil, nil
        inputs.bladestorm_remaining, inputs.bladestorm_duration = nil, nil
        inputs.bladestorm_known = nil
    end

    -- SoD rune reader (nil on Era-base and everywhere else).
    if inputs.sod then
        inputs.raging_blow_remaining, inputs.raging_blow_duration =
            get_guide_cooldown(raging_blow_id)
    else
        inputs.raging_blow_remaining, inputs.raging_blow_duration = nil, nil
    end
    return inputs
end

ST.WARRIOR.guide = {
    slots = is_tbc_guide and guide_slots_tbc
        or (is_era_guide and guide_slots_era
            or (is_wrath_guide and guide_slots_wrath_fury or guide_slots_base)),

    -- Live inputs: the gather above, verbatim, into the caller's reused table.
    gather = function(self, out)
        return ST.WARRIOR.gather_guide_inputs(self, out)
    end,

    -- Pure: the frozen warrior rule matrix (st.warrior_guide in warrior_guide.lua);
    -- guarded so a flavor without that module stays inert rather than erroring.
    -- The composite rage gate (verify §4.2 - BINDING) post-processes the pick:
    -- the engine orders the TBC core by cooldown alone, the gate re-judges the
    -- Bloodthirst prompt against rage (cost + the queued HS/Cleave reserve)
    -- before it reaches the frame, so the label and the guide can never
    -- disagree (this same wrapper feeds get_rotation_key).
    evaluate = function(inputs, out)
        if st.warrior_guide and st.warrior_guide.evaluate then
            st.warrior_guide.evaluate(inputs, out)
            return ST.WARRIOR.gate_composite_action(inputs, out)
        end
        return out
    end,

    -- Static captions (defaults; the RIDE/HOLD text rides out.hold_text).
    labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: warrior slots and the live state provider
--=========================================================================================
-- The slot set mirrors the Next Action Guide's slots (ST.WARRIOR.guide above: the
-- class's top-parse abilities), plus the two trinket slots the HUD serves itself.
-- The TBC fury set (op, execute, slam, hs, bt, ww) is picked on the TBC family,
-- the same six on the ERA family (BT/WW are vanilla spells) and on WRATH by
-- default (fury shape), the base set (op, execute, slam, hs, cleave) everywhere
-- else - the guide's own family split, so the HUD and the guide never disagree
-- about which abilities matter. post_init re-picks through resolve_guide_slots
-- (arms / SoD shapes). The descriptor and provider contracts are frozen
-- in hud.lua's header comment; the "trinket" slots need no provider entry.
--
-- Rank notes: the rank-1 ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Overpower
-- (7384) and Execute (5308) are the ids the rest of this module already matches on;
-- Slam / Heroic Strike / Cleave ship their rank-1 ids from the module's own rank
-- tables. None of the classic-line abilities has a cooldown of its own (Overpower
-- is dodge-gated, Execute health-gated, the rest are on-next-attack or casts), so
-- outside the core families the slots show the running GCD swipe plus the
-- mana/range tints; on TBC and Era Bloodthirst (6 s) and Whirlwind (10 s) carry
-- real swipes (vanilla values, shared by TBC; NEEDS IN-CLIENT CONFIRMATION on
-- 2.5.6 and 1.15.9).
local hud_slot_op = { key = "op", title = "Overpower", kind = "spell", spell = overpower_id }
local hud_slot_execute = { key = "execute", title = "Execute", kind = "spell", spell = 5308 }
local hud_slot_slam = { key = "slam", title = "Slam", kind = "spell", spell = 1464 }
local hud_slot_hs = { key = "hs", title = "Heroic Strike", kind = "spell", spell = 78 }
local hud_slot_cleave = { key = "cleave", title = "Cleave", kind = "spell", spell = 845 }
local hud_slot_bt = { key = "bt", title = "Bloodthirst", kind = "spell", spell = 23881 }
local hud_slot_ww = { key = "ww", title = "Whirlwind", kind = "spell", spell = 1680 }
-- Arms / SoD HUD slots (rank-1 fallbacks; the name-based reads below are
-- rank-agnostic): Rend, Mortal Strike, Bladestorm, Raging Blow.
local hud_slot_rend = { key = "rend", title = "Rend", kind = "spell", spell = 772 }
local hud_slot_ms = { key = "ms", title = "Mortal Strike", kind = "spell", spell = 12294 }
local hud_slot_bladestorm = { key = "bladestorm", title = "Bladestorm", kind = "spell",
    spell = 63784 }
local hud_slot_raging = { key = "raging_blow", title = "Raging Blow", kind = "spell",
    spell = 402911 }
local hud_slot_trinket1 = { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 }
local hud_slot_trinket2 = { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 }

if is_tbc_guide or is_era_guide or is_wrath_guide then
    ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
        hud_slot_hs, hud_slot_bt, hud_slot_ww, hud_slot_trinket1, hud_slot_trinket2 }
else
    ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
        hud_slot_hs, hud_slot_cleave, hud_slot_trinket1, hud_slot_trinket2 }
end

-- Picks the slot set + HUD set from the frozen post_init branch (spec + runes).
-- Defined here (after every slot descriptor above) so all four arms/SoD slots
-- resolve as upvalues, never globals. Called once from post_init, before the
-- shared frame and the HUD build their icons; load-time defaults above serve
-- pre-post_init readers. TBC, Era-base and Wrath-fury keep their load-time
-- sets here (re-assigned identically).
function ST.WARRIOR.resolve_guide_slots(self)
    local arms = self and self.warrior_is_arms == true
    local sod_branch = self and self.warrior_is_sod == true
    if is_wrath_guide and arms then
        ST.WARRIOR.guide.slots = guide_slots_wrath_arms
        ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_rend,
            hud_slot_ms, hud_slot_bladestorm, hud_slot_hs,
            hud_slot_trinket1, hud_slot_trinket2 }
    elseif is_era_guide and sod_branch then
        ST.WARRIOR.guide.slots = guide_slots_sod
        ST.WARRIOR.HUD_SLOTS = { hud_slot_execute, hud_slot_slam, hud_slot_hs,
            hud_slot_bt, hud_slot_ww, hud_slot_raging,
            hud_slot_trinket1, hud_slot_trinket2 }
    elseif is_tbc_guide or is_era_guide then
        ST.WARRIOR.guide.slots = is_tbc_guide and guide_slots_tbc or guide_slots_era
        ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
            hud_slot_hs, hud_slot_bt, hud_slot_ww,
            hud_slot_trinket1, hud_slot_trinket2 }
    elseif is_wrath_guide then
        ST.WARRIOR.guide.slots = guide_slots_wrath_fury
        ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
            hud_slot_hs, hud_slot_bt, hud_slot_ww,
            hud_slot_trinket1, hud_slot_trinket2 }
    end
end

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.WARRIOR.hud_state = {}

-- Localized HUD slot spell names, resolved lazily (name-based cooldown and probe
-- lookups are rank-agnostic). Resolved values are cached; a failed resolution (spell
-- data not ready yet) is retried on the next call, like the guide's filler names in
-- classes/paladin.lua.
local hud_slot_names = {}

local function hud_slot_name(slot)
    local name = hud_slot_names[slot.key]
    if not name then
        name = slot.spell and api.GetSpellInfo(slot.spell) or nil
        if name then
            hud_slot_names[slot.key] = name
        end
    end
    return name
end

-- Full cooldown lengths (seconds) for the swipe when the client reports no real
-- cooldown of its own. Only Bloodthirst and Whirlwind have one on the TBC/Era
-- families (TBC values; NEEDS IN-CLIENT CONFIRMATION on 2.5.6 - the swipe length
-- only matters while a real cooldown is running, which always carries the
-- client-reported length instead). Mortal Strike (6 s, the wotlk 47486 value),
-- Bladestorm (90 s, NEEDS IN-CLIENT CONFIRMATION) and Raging Blow (8 s, the
-- classic 402911 value) serve the arms/SoD slots the same way; Rend has none
-- (its guide swipe follows the debuff window, the HUD shows the GCD).
local HUD_COOLDOWN_FALLBACK = {
    op = 0,
    execute = 0,
    slam = 0,
    hs = 0,
    cleave = 0,
    bt = 6,
    ww = 10,
    rend = 0,
    ms = 6,
    bladestorm = 90,
    raging_blow = 8,
}

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua). Every warrior slot is rotational, so the set is empty and
-- every ready slot shows the running GCD.
local HUD_SKIP_GCD = {}

-- The running GCD (classes/paladin.lua hud_gcd_remaining, verbatim).
local function hud_gcd_remaining(self, now)
    local g = self.gcd
    local expires = g and g.expires
    if type(expires) ~= "number" then
        return 0, 0
    end
    local remaining = expires - now
    if remaining <= 0 then
        return 0, 0
    end
    return remaining, g.spell_length or g.duration or 1.5
end

-- Remaining time and full duration of one warrior ability cooldown: the client's own
-- reading by localized name (rank-agnostic), with the GCD echo filtered (a reading
-- of 1.51 s or less is the running GCD, never one of these abilities' cooldowns -
-- the class's own get_guide_cooldown rule). A missing reading means ready.
local function hud_ability_cooldown(self, slot, now)
    local query = hud_slot_name(slot) or slot.spell
    local start_time, duration = api.GetSpellCooldown(query)
    if start_time and duration and duration > 1.51 then
        local remaining = start_time + duration - now
        if remaining > 0 then
            return remaining, duration
        end
    end
    return 0, HUD_COOLDOWN_FALLBACK[slot.key] or 0
end

-- IsUsableSpell's second return (classes/paladin.lua hud_no_mana, verbatim):
-- through compat's cross-client IsSpellUsable wrapper. A client with no probe
-- reports unknown, rendered as "no tint".
local function hud_no_mana(slot)
    local name = hud_slot_name(slot)
    local ok, _, insufficient = pcall(api.IsSpellUsable, name or slot.spell)
    return ok and insufficient == true
end

-- W7 readiness-glow fallback (verify W7): IsUsableSpell's first return through
-- the same pcall'd wrapper as hud_no_mana above. When the Overpower proc stamp
-- is UNSET (nil - no window was ever armed; the Mainline-code path where the
-- classic dodge window cannot exist), a client that probes the spell as usable
-- right now still gets the glow; a stamp that was armed and has elapsed keeps
-- the window's own verdict instead (the call site's rule). PROBE-ONLY by
-- mandate: never gated on st.is_mainline (the Forever client is Mainline-code
-- but is exactly the client this fallback targets), and a client with no probe
-- - or a secret-guarded unknown - reports "no fallback", never a forced glow.
local function hud_usable_now(slot)
    local name = hud_slot_name(slot)
    local ok, usable = pcall(api.IsSpellUsable, name or slot.spell)
    return ok and usable == true
end

-- WA "spellInRange == 0" (classes/paladin.lua hud_out_of_range, verbatim):
-- api.IsSpellInRange returns 0 out of range, 1/true in range, nil unknown (treated
-- as "not out of range").
local function hud_out_of_range(slot)
    if not (UnitExists and UnitExists("target")) then
        return false
    end
    local name = hud_slot_name(slot)
    if not name then
        return false
    end
    return api.IsSpellInRange(name, "target") == 0
end

-- True when the target is inside the Execute range: its health percentage sits below
-- the guide's threshold (db.guide_execute_pct, default 20 - the engine default in
-- warrior_guide.lua). An unreadable target reads as outside the range, never as in.
local function hud_execute_range(self)
    local health_max = api.UnitHealthMax("target")
    if type(health_max) ~= "number" or health_max <= 0 then
        return false
    end
    local health = api.UnitHealth("target")
    if type(health) ~= "number" then
        return false
    end
    local threshold = self:get_class_table().guide_execute_pct or 20
    return health / health_max * 100 < threshold
end

-- The class provider (frozen contract, hud.lua header): the paladin's ability_state
-- mapping (hud.lua:418-453) re-expressed for the warrior slots. Overpower glows
-- while its dodge window is live (the module's own proc stamp); Execute glows the
-- moment it is ready, in combat, with the target in Execute range.
function ST.WARRIOR.get_hud_state(self, slot, now)
    local s = ST.WARRIOR.hud_state
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    now = now or api.get_time()
    local remaining, full = hud_ability_cooldown(self, slot, now)
    local on_cd = remaining > 0
    if on_cd then
        s.remaining = remaining
        s.duration = full
        s.text_remaining = remaining
        s.desaturate = true
    elseif not HUD_SKIP_GCD[slot.key] then
        -- The GCD shows as a swipe (WA "show GCD"); the HUD's 2 s rule keeps its
        -- text hidden.
        local g, gd = hud_gcd_remaining(self, now)
        if g > 0 then
            s.remaining, s.duration = g, gd
            s.text_remaining = g
        end
    end

    local db = self:get_class_table()
    if db.hud_mana_tint and hud_no_mana(slot) then
        s.usable = false
    end
    if db.hud_range_tint and hud_out_of_range(slot) then
        s.in_range = false
    end

    if slot.key == "op" then
        -- The dodge window (the module's own proc stamp) arms the glow; the W7
        -- fallback arms it too while the client probes the spell as usable
        -- right now. A live window short-circuits the probe (one fewer read
        -- while the stamp is live); a stamp that is set but elapsed is the
        -- window's own verdict and stops the glow - the probe only covers a
        -- client that never armed a window at all (the Mainline-code path
        -- where the classic dodge window cannot exist), never a window that
        -- came and went.
        local op_remaining = self.WARRIOR.get_overpower_remaining(
            self.warrior_overpower_proc_until, now)
        if op_remaining ~= nil then
            s.glow = true
        elseif self.warrior_overpower_proc_until == nil then
            s.glow = hud_usable_now(slot)
        else
            s.glow = false
        end
    elseif slot.key == "execute" then
        s.glow = (remaining <= 0 and self.in_combat == true
            and hud_execute_range(self)) or false
    end
    return s
end

--=========================================================================================
-- Rotation text: the warrior rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the paladin's shape (ST.PALADIN.
-- get_rotation_key in rotationtext.lua): the guide's own decision, so the label and
-- the guide can never disagree. The warrior engine names no rotations (its
-- out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), HOLD while the engine holds, RIDE while it
-- rides, nil when the guide is idle (renders as the empty text). No practice
-- branch: Twist Practice is paladin-only (no simulation exists for this class).
-- One reused output table: no per-tick allocation on the label tick.
ST.WARRIOR.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
local rotation_name_cache = {}

local function rotation_ability_name(action)
    local spell_id
    local slots = ST.WARRIOR.guide.slots
    for i = 1, #slots do
        if slots[i].key == action then
            spell_id = slots[i].spell_id
            break
        end
    end
    if spell_id then
        local name = rotation_name_cache[spell_id]
        if not name then
            name = api.GetSpellInfo(spell_id)
            if name then
                rotation_name_cache[spell_id] = name
            end
        end
        if name then
            return name
        end
    end
    return action
end

function ST.WARRIOR.get_rotation_key(self)
    local guide = ST.WARRIOR.guide
    local engine = st.warrior_guide
    if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
        return nil
    end
    local out = guide.evaluate(guide.gather(self, ST.WARRIOR.guide_inputs),
        ST.WARRIOR.rotation_out)
    if out.action ~= nil then
        return rotation_ability_name(out.action)
    end
    if out.hold then
        return out.hold_text
    end
    return nil
end

if st.debug then st.utils.print_msg('-- Parsed classes/warrior.lua module correctly') end
