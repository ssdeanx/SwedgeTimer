# SwedgeTimer — Missing Features Discovery Report

**Date:** 2026-10-17
**Sources:** SuperSwingTimer (curseforge), TellMeWhen, Quartz, Gnosis, ClassTimer, gh_grep (Quartz Swing module), SwedgeTimer brainstorm bank (40 ideas).
**Method:** READ-ONLY external research. No repo files edited except this report. No git operations.
**Uncertainty markers:** items marked `(uncertain)` where source coverage is thin or client-specific behavior unverified.

## Competitor feature inventory (what they have that we don't)

### SuperSwingTimer (direct competitor, Classic/TBC)
Source: https://www.curseforge.com/wow/addons/super-swing-timer

- Enemy swing bar (current hostile target MH swing timer) — driven by PLAYER_TARGET_CHANGED, UnitGUID, UnitAttackSpeed, hostile SWING_DAMAGE/SWING_MISSED, ignoring off-hand hits.
- Class power bars (rage/energy/mana) numeric-only, bottom-most bar of swing stack, 10px fixed height, event-driven (UNIT_POWER_*).
- Hunter: 4-state Range Helper (melee/sweet spot/ranged/OOR) with configurable colors/width; aspect/stance icon; adaptive 25x25 CD/buff icon group (BW, RF, TBW, Quick Shots, Rapid Killing, Kill Command, Readiness, Misdirection, Aspect of Hawk, Trueshot Aura, racials) with gold glow last 4s; 7 target debuff bars (Serpent Sting, Wing Clip, Concussion Shot + 4 traps) with spell icons + gold glow + dynamic stacking; SoD rune tracking (Melee Specialist, DW Spec, Aspect of Viper, Flanking Strike, Carve).
- Warrior: Battle Shout + Overpower proc tracking; SoD runes (Quick Strike, Raging Blow, Devastate, Blood Surge, Precise Timing, Rampage).
- Druid: Clearcasting/Omen of Clarity proc tracking; SoD runes (Savage Roar, Wild Strikes, Berserk, Mangle, Lacerate, Survival Instincts); form-aware power bar.
- Paladin: buff/CD icon group (AW, Divine Shield, HoJ, BoP, Holy Wrath, LoH, racials) gold glow last 4s; SoD runes (Aegis, Hand of Reckoning, Guarded by Light, Sacred Shield, Fanaticism, Art of War, Divine Storm, Crusader Strike).
- Shaman: Rockbiter Weapon tracking; Lightning/Water Shield 3-charge tracker; Flame Shock target bar; SoD runes (Maelstrom Weapon, Way of Earth, Shield Mastery, Molten Blast, Lava Lash).
- Rogue: Slice and Dice bar, energy-tick helper, Sinister Strike end-window red slice, energy tick cadence. (Rogue not a SwedgeTimer class — out of scope but noted.)
- Masque-compatible? No (SuperSwingTimer uses own textures). TellMeWhen does Masque.

### TellMeWhen
Source: https://www.curseforge.com/wow/addons/tellmewhen

- 110+ conditions engine; sounds on attribute change; text announcements; transparency levels; status bars on icons; Masque skinning; counters (/tmw counter); CPU profiling (/tmw cpu); raid cooldown tracking (others' cooldowns); diminishing returns; totems; ICDs; spell casts; reactive abilities.

### Quartz
Source: https://www.curseforge.com/wow/addons/quartz

- Target/focus cast bars; buffs/debuffs as duration bars; flight progress; GCD spark; interrupt color + who interrupted; latency bar at end of cast bar; mirror timers (breath, feign death, party invite, resurrect timeout, arena start); range recolor mid-cast; swing timer; custom timers; tradeskill merge.

### Gnosis
Source: https://www.curseforge.com/wow/addons/gnosis

- Unlimited bars; single-bar buff/debuff/cooldown/item timers; horizontal/vertical; invertable growth; black/whitelist; channeled spell ticks with spellpushback; combine DPS of channeled spells to combat text; anchor bars to frames/mouse; multi-spell timers (one bar handles many spells, shows highest priority); manual timer start via slash.

### ClassTimer
Source: https://www.curseforge.com/wow/addons/classtimer

- Simple buff/debuff timers player/target/focus; icons+time or bars; customizable text tokens (%s spell, %a apps, %u unit, %n mob); SharedMedia textures. (Deprecated → WeakAuras.)

## Ranked missing-feature table (NEW, not in 40-idea bank)

Effort: S (<1 day), M (1-3 days), L (>3 days). Offline-implementable: Y = pure logic/testable without client; N = needs in-client verification.

| # | Feature | Who has it | Parse/training value | Effort | Offline Y/N | Notes |
|---|---------|-----------|----------------------|--------|-------------|-------|
| 1 | Enemy swing bar (current hostile target MH swing timer) | SuperSwingTimer | H (PvP/duel + melee timing) | M | N | Needs CLEU hostile SWING_* + UnitAttackSpeed; secret-value guards on retail. (uncertain on Forever) |
| 2 | Class power bars (rage/energy/mana) numeric, bottom of stack | SuperSwingTimer | M (resource awareness) | M | Y (math) | Event-driven UNIT_POWER; complements HUD. |
| 3 | Hunter CD/buff icon group (BW, RF, TBW, Quick Shots, Rapid Killing, Kill Command, Readiness, Misdirection, Aspect of Hawk, Trueshot Aura, racials) gold glow last 4s | SuperSwingTimer | H (cooldown stacking) | M | Y | Extends existing HUD slots; ids need verification. |
| 4 | Hunter target debuff bars (Serpent Sting, Wing Clip, Concussion Shot + 4 traps) with icons + gold glow + dynamic stacking | SuperSwingTimer | M-H (DoT uptime) | M | Y | New tracker set; ids per family. |
| 5 | Paladin CD icon group (AW, Divine Shield, HoJ, BoP, Holy Wrath, LoH, racials) gold glow last 4s | SuperSwingTimer | M (cooldown awareness) | S-M | Y | Extends HUD; ids need verification. |
| 6 | Shaman Rockbiter Weapon tracking | SuperSwingTimer | S-M (weapon imbue uptime) | S | Y | New badge; id verify. |
| 7 | Shaman Lightning/Water Shield 3-charge tracker | SuperSwingTimer | M (shield charges) | S | Y | SwedgeTimer has shield row; charge count may be missing. (uncertain) |
| 8 | Druid Clearcasting/Omen of Clarity proc tracking | SuperSwingTimer | M (free cast awareness) | S | Y | New proc glow; aura id verify. |
| 9 | Warrior Battle Shout tracking | SuperSwingTimer | S-M (buff uptime) | S | Y | New buff bar; id verify. |
| 10 | Target/focus cast bars | Quartz | M (interrupt timing) | M | N | New frames; interrupt color. |
| 11 | Mirror timers (breath, feign death, party invite, resurrect timeout, arena start) | Quartz | S (utility) | S-M | N | New timer set. |
| 12 | Latency bar at end of cast bar (Quartz-style) | Quartz | M (cast cancel timing) | S | Y | Visual; latency already cached. |
| 13 | Range recolor mid-cast | Quartz | M (range awareness) | S | Y | Reuse range helper. |
| 14 | Multi-spell timer bars (one bar, many spells, highest priority) | Gnosis | M (compact UI) | M | Y | New bar type; priority sort. |
| 15 | Channeled spell tick markers with spellpushback | Gnosis | M (channel classes not in scope) | M | N | Low priority (no channel classes supported). |
| 16 | Combine DPS of channeled spells to combat text | Gnosis | S | S | N | Low priority. |
| 17 | Anchor bars to frames/mouse cursor | Gnosis | S (UX) | S | Y | Design-mode enhancement. |
| 18 | Masque skinning support | TellMeWhen | S (cosmetic) | M | N | New dependency; optional. |
| 19 | Conditions engine (110+ condition types) | TellMeWhen | M (advanced users) | L | Y (logic) | Large scope; maybe subset. |
| 20 | Sounds on attribute change (configurable) | TellMeWhen | M (sensory) | S-M | Y | Reuse twist sound map; expand. |
| 21 | Text announcements on attribute change | TellMeWhen | S-M | S | Y | Reuse rotation text. |
| 22 | Counters (/tmw counter style) | TellMeWhen | S (tracking) | S | Y | Simple counter widget. |
| 23 | CPU profiling (/tmw cpu style) | TellMeWhen | S (perf) | S | Y | /st diag counters (banked C4). |
| 24 | Raid cooldown tracking (others' cooldowns) | TellMeWhen | M (raid utility) | M-L | N | Needs COMM/aura scan of raid; scope creep. |
| 25 | Diminishing returns tracking | TellMeWhen | S (PvP) | M | N | PvP-focused; low parse value. |
| 26 | SoD rune tracking (all classes) | SuperSwingTimer | M (SoD players) | M-L | N | Many ids; SoD-specific. (uncertain ids) |
| 27 | 4-state Range Helper (melee/sweet spot/ranged/OOR) | SuperSwingTimer | M (positioning) | S | Y | SwedgeTimer has weave_range + range strip; may overlap. Verify before adding. |
| 28 | Aspect/stance icon (hunter) | SuperSwingTimer | S | S | Y | SwedgeTimer hunter has aspect? (uncertain) |
| 29 | Flight progress bar | Quartz | S (utility) | S | N | Low parse value. |
| 30 | Tradeskill merge (combine repeated casts) | Quartz | S (crafting) | S | N | Low parse value. |
| 31 | Profile export/import string | (ergonomics) | M (adoption) | M | Y | Banked C5 parse presets touches this; export string is new. |
| 32 | Facing/behind-target indicator | (movement) | M (melee positioning) | M | N | New sensor; not in bank. |
| 33 | Number of enemies in melee range | (target sensors) | M (AoE decisions) | M | N | Nameplate scan; overlaps H3/S6 target count. |
| 34 | Aggro/threat indicator | (target sensors) | S-M (tank awareness) | S | N | UnitThreatSituation; low parse value for DPS. |
| 35 | Titanforge-specific gaps (custom spells/runes?) | (Forever/Titanforge) | ? | ? | N | (uncertain — no source found; needs in-client probe) |

## Next-level differentiators nobody has

1. **Parse replay / post-fight timeline export** — record swing timeline + decisions during a fight, export to a reviewable format (CSV/JSON) for post-raid analysis. No addon in this set does in-addon replay. Value H for parse chasers. Effort L. Offline Y (data model) / N (WoW file I/O limits).
2. **Adaptive practice difficulty** — sim adjusts move windows / rage income to player skill, targets weak points (e.g., if twist hit-rate < 60%, narrow window). Value H for learners. Effort M. Offline Y.
3. **Real-time DPS delta vs sim** — compare live performance to simc-expected, highlight losses in real time (e.g., "you lost 120 DPS to clips this fight"). Value H. Effort L. Offline N (needs simc data + combat log).
4. **Ghost overlay** — show a top-parse player's swing timeline ghost for comparison during practice. Value M-H. Effort L. Offline Y (data) / N (source data).
5. **Auto-calibration of latency/deadzone** — observe actual swing data to calibrate deadzone/latency instead of manual tuning. Value M. Effort M. Offline Y (math) / N (data collection).

## Verification notes / uncertainty

- SuperSwingTimer feature list sourced from curseforge description (scraped 2026-10-17). SoD rune ids and Titanforge/Forever behavior not verified in-client.
- TellMeWhen/Quartz/Gnosis/ClassTimer features from curseforge descriptions; versions may be outdated for current clients.
- WeakAuras swing suites not directly scraped (wago.io is JS-rendered; search endpoints unavailable). Claims about WeakAuras patterns are inferred from ClassTimer deprecation note + general knowledge — mark as (uncertain).
- firecrawl_search was non-functional during this session; gh_grep rate-limited. Research relied on direct page scrapes.
- No repo files were modified. No git operations performed.

## Cross-check against banked 40 ideas

The 40 banked ideas (H1-H7, W1-W7, P1-P7, D1-D7, S1-S7, C1-C6) are NOT re-proposed here. Items above are additive. Overlap risks: #27 (4-state range helper) overlaps H4/C? range gate; #3 (hunter CD group) overlaps H6 BW badge; #5 (paladin CD group) overlaps P2 JotC; verify before implementing to avoid duplicate UI.