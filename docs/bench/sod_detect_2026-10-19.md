# SoD vs Era runtime detection — finding 2026-10-19

Read-only investigation. No addon file changed. Scope: `compat.lua` (family
detection), `tests/smoke.lua` (family profiles), `bench/verify_bank.md`
(SoD items), plus `wow-ui-source` branch names only (no deep reads).

## 1. How family detection works today

`compat.lua:49-97`: preferred signal is `WOW_PROJECT_ID` constants
(`WOW_PROJECT_CLASSIC`=2 → `"ERA"`, plus TBC/WRATH/CATA/MISTS/MAINLINE and
`WOW_PROJECT_CAMELOT`=18 → `"FOREVER"`); fallback is the TOC interface
number (`major == 1` → ERA, with `>= 16000` carved out to FOREVER,
`compat.lua:77-96`). Result lands in `st.family`, with
`st.is_mainline` (RETAIL/FOREVER), `st.gcd_probe_spell_id`
(`compat.lua:106-113`), `st.lust_supported` (`compat.lua:127`), and
`st.cleu_supported` (`compat.lua:1006`).

`tests/smoke.lua` pins every branch: ERA project 2 (`:183`), legacy TOC
fallback 20506→TBC (`:213`), 16001→FOREVER (`:229-233`), RETAIL project 1
(`:267-270`), FOREVER project 18 (`:284-289`). There is **no SoD profile**
and no SoD project constant anywhere in `compat.lua` or `smoke.lua`.

## 2. What is identical between SoD and Era clients (offline)

- Same project id (`WOW_PROJECT_CLASSIC` = 2) and same interface line:
  AGENTS.md matrix ships Classic Era / SoD 1.15.9 together on `_Vanilla`
  (11509); the base toc advertises the same number for both.
- Same classic API surface: `GetSpellInfo` global, `UnitAura`, classic
  combat log (`CombatLogGetCurrentEventInfo` present → `cleu_supported`
  true on both), same GCD probe 29515, same `lust_supported == false`
  (Bloodlust/Heroism is TBC+ only — `bench/verify_bank.md` §2:21).
- `wow-ui-source` branch list (2026-10-19) has **no SoD-specific branch**
  (`classic_era`, `classic_anniversary`, `classic_titan`, `classic`,
  `forever`, `live`, `ptr`, … — no `sod` branch local or remote). SoD
  shares the Era code line, matching the single-`_Vanilla`-toc ship.

Conclusion: **no offline discriminator exists** — project id, interface
number, toc, and API-presence probes all answer identically on SoD and
Era-base. Any interface/build-string split would be guessing.

## 3. What differs at runtime (the only usable signal)

The spell book. A SoD client with runes engaged knows SoD-only spells an
Era-base client can never know. The tree already uses this per class —
never a family token, never a version string:

- Hunter: Chimera Shot rune 409433 (gloves rune) — `classes/hunter.lua:116-122`,
  detector `api.is_spell_known(409433)` at `:951`, slot swap at `:952-956`;
  contract restated `hunter_guide.lua:52-59`, gate `st.family == "ERA" and
  inputs.chimera_known == true` at `:688`. Sim rune ids LnL 415413 / Sniper
  415399 / Viper 415423 (`bench/hunter_rotation_audit_2026-10-19.md:10`).
- Paladin: `is_sod_client(cs_known, ds_id)` — `classes/paladin.lua:1189-1205`
  (ERA-gated; CS rune known, or DS resolve non-nil, or
  `api.is_spell_known(348700)` Martyr leg); narrows twist 400 ms → 200 ms
  at `:1222-1226`, FCFS `sod` mode at `:2842-2843`.
- Druid: `sod_runes_present()` — `classes/druid.lua:1452-1500` (id-first via
  `api.is_spell_known` over `druid_mangle_ids`, English-name fallback
  Mangle/Savage Roar; latched, callers gate to the ERA token); fed as
  `inputs.sod_runes` at `:1739`.
- Shaman: MW aura-observed latch — `classes/shaman.lua:649-660`
  (`weave_mw_observed` set on a positive MW count),
  `weave.has_maelstrom_weapon(family, mw_observed)` (`weave.lua:64-88`:
  ERA+observed → true, ERA-never-observed → false, TBC always false);
  ids 408505 (SoD) / 53817 (Wrath) at `classes/shaman.lua:31-33`. Sim gate
  shape matches (`auraIsKnown(408505)`,
  `bench/shaman_rotation_audit_2026-10-19.md:105,182`).
- Warrior: `is_sod_client()` — `classes/warrior.lua:251-258` (ERA-gated;
  Raging Blow 402911 or Consumed by Rage 425440 known via
  `api.is_spell_known`), frozen at post_init (`:566`), SoD slot set + floor
  60 at `:2672-2679`, `:2447-2451`. SoD Blood Surge aura 413399 vs Wrath
  46916 (`:47-49`); Sudden Death ids 52437/440495 (`:208-211`).
- Rogue: SOD Envenom-primary data + verdict already ship
  (`rogue_guide.lua:351-360`, `ENVENOM_RULES.SOD`) but are unreachable —
  header marks SoD detection a filed follow-up (`:35-36`, `:173-174`);
  SoD builder/finisher ids Saber Slash 424785 / Mutilate 399956 / Envenom
  rune 399963 (`bench/rogue_rotation_audit_2026-10-19.md:73-74,238`).
- Druid audit model is already ERA-token + flag:
  `bench/druid_rotation_audit_2026-10-19.md:53,79`
  (`inputs.family == "ERA"`, `sod_runes == true`).

UNCONFIRMED (no source in tree, do not probe offline): a `C_Engraving` /
rune-loadout namespace, `C_SeasonInfo` or similar season API, a
SoD-specific build-string suffix, an interface-number split inside 1.15.x.
The only `GetRune*` hits in-tree are death-knight `GetRuneCooldown` /
`GetRuneCount` in `Libs/LibClassicDurations/.luacheckrc` — a different
system, not SoD engraving. `verify_bank.md` §2:20 notes Berserk(cat)
50334 as "Classic Era/SoD: not baseline (SoD rune)" — same spell-book
logic, not a family signal.

## 4. Recommendation — ONE mechanism

**Per-class SoD-only spell-knowledge probe through the existing compat
`api.is_spell_known`, gated on `st.family == "ERA"`.** No global
`st.is_sod`, no `st.family == "SOD"`, no version/interface branching.

Gating shape (already the tree convention — copy it, don't invent a second one):

```lua
-- SoD-only: st.family == "ERA" and this player's book knows the rune.
-- Strict == true; nil/false (unknown/unlearned) reads Era-base.
local is_sod = st.family == "ERA"
    and api.is_spell_known(<SoD-only spell id>) == true
```

Rules:
1. Probe **knowledge** (`api.is_spell_known`, strict `== true`), never
   spell-data existence (`GetSpellInfo` answering for an id proves
   nothing) — druid `:1466-1475` states why.
2. Probe **SoD-only ids** (drifts with class: 409433 hunter, 348700/CS/DS
   paladin, Mangle-table druid, 402911/425440 warrior, 424785/399956/399963
   rogue candidates, 408505-shaman via the aura latch). Each id needs
   in-client confirmation before use.
3. Aura-granted systems (shaman MW) use the **observed latch**, not a bare
   knowledge read (`weave_mw_observed` + `has_maelstrom_weapon`).
4. Freeze/latch at post_init (warrior `:566`, druid `:1488-1500`): a rune
   (un)learned mid-session needs `/reload`. Document that.
5. Rogue closes its filed gap by wiring `ENVENOM_RULES.SOD` behind this
   shape (ERA + its rune probe), not by waiting for a family token.

## 5. Why not the alternatives

| Candidate | Verdict |
|---|---|
| New `WOW_PROJECT_*` / `st.family == "SOD"` | Impossible offline: SoD reports CLASSIC=2; no constant exists in tree or smoke profiles. |
| Interface/build-string split | Rejected: same 1.15.x line, same `_Vanilla` toc; any cut value is a guess. |
| `C_Engraving` / season-API probe | UNCONFIRMED: zero hits in tree; inventing the namespace risks a nil-probe that silently reads Era-base forever. In-client check only. |
| Global `st.is_sod` helper | Rejected: runes are per-class spell books; a hunter rune says nothing about a druid's book. Per-class probes already carry this correctly. |
| Name-based detection as primary | Fallback only (druid `:1479-1486`): locale-bound, English-only. Id probe carries. |

## 6. In-client validation (owner: orchestrator)

On a SoD client and an Era-base client, side by side: for each class
probe above, record `api.is_spell_known(<id>)` learned/unlearned, confirm
the SoD-only ids, and confirm no Era-base false-positive; confirm the MW
aura latch observes 408505 on SoD and never on Era-base; optionally check
`rawget(_G, "C_Engraving")` / season namespaces and `GetBuildInfo`
strings and report back as CONFIRMED or UNCONFIRMED — do not wire
anything not confirmed.
