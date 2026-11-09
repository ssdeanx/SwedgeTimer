# bench/paladin_followups_2026-10-19 — Paladin follow-ups: built engine-side, remainder filed

Desk: paladin-followups. Date: 2026-10-19.
Scope: `classes/paladin.lua`, `twist.lua`, `nextaction.lua`, `tests/paladin_state.lua`,
`tests/twist_state.lua`, `tests/nextaction_state.lua`, `compat.lua` (probe only).
No addon file outside scope touched; no git; no bench overwrite.
In-client behavior UNCONFIRMED throughout; sim-match is not client proof.

Source audits: `bench/paladin_rotation_audit_2026-10-19.md` (19 rows, hidden
techniques 1-2/4-6), `bench/wrath_sod_2026-10-19.md` §4 (SoD variant set),
`desks/paladin-fixes/journal.md` (filed list this lane builds from).

## 0. Compat verification (no edit)

`compat.lua:160-176` already wraps `GetSpellInfo` on every family and returns
`castTime` 4th (classic global ms; `C_Spell` form maps `info.castTime` to the
same position; unknown client reports 1500). The shaman catalogue
(`classes/shaman.lua:334-335`) and the hunter Steady probe
(`classes/hunter.lua:1159-1164`, `cast_ms / 1000`) already consume it as
milliseconds. Verdict: cast-time probe PRESENT — no compat change made
(per dispatch: probe groundwork only if verified missing).

## 1. Built (engine + provider, nil-safe, no default-visible change)

All new engine inputs default to archived behavior (nil/false = archived);
all new display fields are ignored by `nextaction_ui.lua:display_active`
(fixed-field reads, unknown keys map to nil via `ui.slot_index`), so nothing
renders until a UI lane consumes them. Swing-activity gating throughout; no
`st.is_mainline`-alone branch added.

| # | Item | Built | File:line |
|---|---|---|---|
| 1 | Stopattack discipline | Advisory `out.stopattack`: true when a twist-now or a judge cues while `swing_remaining <= twist_window` (classic `IsUsingJudgementStopAttack` + SoD StopAttack/StartAttack twists/judges). `twist_now` latches the two immediate-cue branches (`nextaction.lua:511,823,845`). Macro/UI that acts on it is filed (addons cannot cast). | `nextaction.lua:34-37,511,823,845`; mapping `classes/paladin.lua:3035` |
| 2 | Prepull guidance | `PREPULL_SEAL_LEAD_SECONDS = 1.5` (classic APL −1.5 s) + `out.prepull_ready` (window open, `seal == "none"`, NaN/negative-safe). Provider feeds nil (no pull-timer source in scope). | `nextaction.lua:74-76,386-388,826-832,846`; provider `classes/paladin.lua:2803-2808` |
| 3 | SoD seal-maintenance | FCFS SoD only: `SEAL_MAINTAIN_RESEAL_SECONDS = 1` (classic APL remaining<1 line, same as `get_seal_state` freshness). Expiring seal elevates a ready Judge above the damage order through the existing judge channel; `out.seal_maintenance` carries the reseal half for the future slot. Provider feeds nil (per-SoD-build seal source UNCONFIRMED — the Exodin maintained seal's role mapping is not in the audit, so the SoC aura is not guessed). Wrath keeps the archived order. | `nextaction.lua:77-80,390-393,1024-1029,1045-1049,1091`; mapping `classes/paladin.lua:3037` |
| 4 | SoD build variants | Per wrath_sod §4: Twist MATCH kept as-is; Exodin kept + maintenance above; Seal-stacking / Shockadin 1H/2H / Wrath-like cut-with-reason (see §2). No new `fcfs_mode`; unknown modes still prompt nothing (pinned). | `nextaction.lua:1045-1049` (+ §2 below) |
| 5 | Cast-time probe | Live provider feed: `get_guide_how_cast_seconds` reads `select(4, api.GetSpellInfo(id))` ms → s, cached per resolved rank, nil while unknown (Era/Forever only — the only families whose engine reads it). 0 = instant (Forever sim shape), nil = archived hp-only rule. | `classes/paladin.lua:1983-2001,2909` |
| 6 | Mana-threshold groundwork | Read path only: `db.twist_mana_threshold_pct` (percent, nil = off = archived) → `inputs.twist_mana_threshold` (engine plug pre-exists). No widget, no default. | `classes/paladin.lua:2811-2819` |
| 7 | Hard-wait UI groundwork | `inputs.strict_sequence` (true on SoD rune builds via existing `is_sod_client`) + `out.hard_wait` (strict and holding). Render filed. | `nextaction.lua:84-86,836,849`; provider `classes/paladin.lua:2897` |
| 8 | Rank-1 advice | Live reader VERIFIED (`api.is_spell_known(20375)`; rank probes already gate CS/DS/HoW the same way) → `inputs.soc_rank1_known` → `out.rank1_advice` on the twist tree (FCFS never advises). Slot + option filed. | `nextaction.lua:81-83,833,848`; provider `classes/paladin.lua:2821-2824`; mapping `classes/paladin.lua:3038` |

`twist.lua`: no change. Nothing in the follow-ups lives in the pure twist
state machine (attempt/success/ICD/window): the advisories belong to the cue
sites (`nextaction.lua`) and their feeds (`classes/paladin.lua`).

## 2. SoD variants filed (per wrath_sod §4 — build nothing beyond it)

| Variant | Verdict | What's missing (filed need) |
|---|---|---|
| Twist (SoC↔SoM, `p8-twist`) | MATCH, kept | — |
| Exodin (`p8-exodin`) | Kept + maintenance (§1.3) | Reseal slot + `nextaction_ui` render + provider seal map (see §3) |
| Seal-stacking (`p8-stack`) | Cut-with-reason | Separate stack-maintenance state machine; only the build name from `retribution_test.go` exists in scope — no APL fetched, no design |
| Shockadin 1H/2H | Cut-with-reason | Spellpower gear/talent basis; guide has no spellpower inputs; no APL fetched |
| Wrath-like (`p8-wrath`) | Cut-with-reason | Its APL unfetched; aliasing the WRATH table onto ERA/SoD would prompt uncastable buttons (wrong spell ids/cooldowns) |

## 3. Filed (needs out-of-scope files — precise need each)

- Rank-1 advice slot + option: needs a new guide slot (`ST.PALADIN.guide.slots`
  shape, `classes/paladin.lua:2886+`) + `nextaction_ui` render + options widget/default.
  Engine half live (§1.8).
- Judgement/twist stopattack macro + UI: needs a macro/UI lane; engine advisory
  live (§1.1). Addons cannot cast — this stays advisory by design.
- Prepull seal cue: needs a pull timer source (`main.lua`, encounter/pull API)
  → `inputs.time_to_pull_seconds`; seal choice is family-specific (TBC prepulls
  Crusader, not in the engine). Engine half live (§1.2).
- SoD seal-maintenance slot: needs the per-SoD-build seal-aura source
  (UNCONFIRMED role mapping — do not guess SoC) + new guide slot +
  `nextaction_ui` render + provider map. Judge elevation + advisory live (§1.3).
- SoD variant selector: needs options widget + dispatch (Shockadin/Seal-stacking/
  Wrath-like are separate rotations, not FCFS parameters). See §2.
- `fight_remaining_pct`: needs a boss-HP/encounter-timer source. Still nil.
- `twist_mana_threshold` value: needs options widget + default for
  `db.twist_mana_threshold_pct` (percent, nil = off). Read path live (§1.6).
- strictSequence hard-wait render: needs `nextaction_ui` hold-state render for
  `out.hard_wait`. Engine + feed live (§1.7).
- `how_cast_seconds` in-client confirmation: probe live but Forever HoW
  instant-timing is beta-UNCONFIRMED; confirm against the running client.

## 4. Validation

- Suites: `nextaction_state` 526 (was 477), `paladin_state` 316 (was 295),
  `twist_state` 84 (untouched). Full harness: **37 steps, 0 failed**.
- luacheck: 0/0 on all six touched files (`compat.lua` untouched by this lane;
  the 3 tree warnings are `compat.lua:36` pre-existing + `druid_guide`/`main`
  sibling-owned).
- Mutations 10/10 killed on `/tmp/opencode/palfu` copies (engine stopattack /
  maintenance / prepull-lead / hard-wait / rank-1; provider cast-units /
  mana-cap / strict / mapping / rank-1-reader); copy restored clean, suites
  re-green.
- Owner: orchestrator. In-client test session per standing rules (nothing here
  is client-proven).
