# Hunter weave-distance lane — build report 2026-10-19

Desk: hunter-wa-leftovers. Scope: classes/hunter.lua, hunter_guide.lua,
hunter_ui.lua, tests/hunter_state.lua, tests/hunter_guide_state.lua.
Brief chain: bench/hunter_wa_map_2026-10-19.md Secs 1-3 (Dynamic switch,
rotLogicMode 3) + operator pointers (LibRangeCheck-2.0 first; wago J3U7jOhMI
"Melee weave - Distance approximation" prog model; C_Spell ruling).

## Built (wired with pins)

- `classes/hunter.lua:962-978` `ST.HUNTER.get_weave_band(in_melee_range,
  in_ranged_range, min_range, max_range)` — pure band over main's
  LibRangeCheck poll: melee wins (the Mode-2 trigger analog; the lib's 5 yd
  checker family answers it, item 8149 among them), then ranged (hunter 35 yd
  checker), then known-band-beyond as out_of_range, else nil (unknown hides).
  No new probe, no family branch, no C_ spell calls.
- `classes/hunter.lua:1581-1585` gather writes `inputs.weave_band` every call
  off `self.in_melee_range / self.in_ranged_range / self.target_min_range /
  self.target_max_range` (main.lua:1425-1517 `init_range_finders`/`rf_update`,
  0.05 s poll, lrc_unavailable deadline fallback — main-owned).
- `hunter_guide.lua:208-224,355` frozen-input doc for `weave_band` + mapping
  verdict (Dynamic switch onto 2b HOLD / clip-gated weave / RIDE). Zero
  behavior change.
- Pins: `tests/hunter_state.lua` Sec 20 (band precedence incl. 0/false vs
  unknown, TBC+Era family-independence, gather end-to-end incl. stale clear);
  `tests/hunter_guide_state.lua` forged-band block (forged bands change
  neither action nor overlay; 2b HOLDs on probe 0 in every band);
  Sec 20b filed-state pins (no IsItemInRange / item:8149 / C_Spell / CLEU in
  the three impl files).

## Filed with reason (sim wins conflicts)

- Traps (map Sec 6): trap machines need main.lua CLEU (out of scope); sims
  treat traps as LnL source only (hunter_open Sec 1). Filed, no code.
- Item-8149 hand probe: the vendored lib owns item 8149 as its 5 yd checker
  (LibRangeCheck-2.0.lua:200,305) with fallbacks; main publishes it. Filed.
- Engine arm (distance-gated prompt/mode): stateless engine cannot express
  wait-at-melee/move timing (hunter_open Sec 1 CUT precedent); no sim
  switches prompts by distance; WA "3w/2w" label semantics UNCONFIRMED.
- Prog live wiring + widget (bar, 50% tick, red/purple, colors): needs the
  filed widget (options out of scope) and compat speed/dir probes (no
  GetUnitSpeed in compat — filed). Spec below is the widget lane's build doc.
- Per-family LRC liveness: main-owned (pinned by tests/main_init_state.lua +
  diag lrc states); hunter reads nil-safe, no family branch. Gap filed there.

## C_Spell reconciliation (operator ruling, authoritative)

C_Spell-with-id works in the WA context, NOT in the addon context. TBC addon
paths stay NAME-based, no exceptions; the WA's `C_Spell.IsSpellInRange(2974)`
is model evidence only (enter/exit semantics), never API-shape evidence.
Pinned: no `C_Spell` literal anywhere in the hunter scope (Sec 20b).

## Prog build spec (filed widget lane — OPERATOR-REPORTED dynamics, wago J3U7jOhMI; header/description SCRAPE-CONFIRMED 2026-10-19, see Evidence below)

Extraction: the wago page was formerly a JS shell (webfetch empty;
no-wait firecrawl_scrape returned markdown:"" with status 200). The
waitFor:8000 recipe (bench/weakaura_templates_2026-10-19.md §6,
re-verify round) now renders the full page — header, stats and
description CONFIRMED — but the scrape returns rendered markdown, not
WA Lua: no Lua extracted, so the per-tick dynamics below remain the
operator's spec, marked accordingly — in-client validation owed.

- State `prog` in [-0.7, +0.7], bar range -.7/.7, boundary tick at 0 (50%).
  Melee side negative, ranged side positive. WA colors: melee red,
  non-melee purple (our strip keeps its palette — no default-visible change).
- Per tick: `prog += dir * (speed_yds / 7) * delta`; if `speed < 4.6` flip
  `dir` (backpedal band); clamp to ±0.7; boundary enter/exit (lib
  in_melee_range flip) forces 0 (re-anchor, beats everything); target moving
  forces the +/-0.7 snap on the current side (+0.7 from exactly 0);
  unknown/degenerate inputs hold prev (prev defaults to 0).
- Live inputs needed: player speed + movement sign + target-motion flag
  (compat probes, filed) and the lib flip (main-owned). Pure core verified
  during development (25 math pins incl. the 4.6/4.59 boundary, all killed
  their mutants) but REMOVED before landing: with no live caller it is a
  dead hook and wiring_check check 2 fails the harness; self-accepting would
  hide it. The widget lane re-lands this exact core with its caller + pins.

## Validation (owner: orchestrator)

- Harness `bash tests/run.sh`: 38 steps, 0 failed. luacheck: 2 warnings /
  0 errors (floor held). Scope suites: hunter_state 673, hunter_guide_state
  1145 checks green.
- Mutations on /tmp/opencode tree copies (removed after): M1 band melee leg
  killed (6 fails), M2 gather band write removed (5 fails), M3 nil-hide
  broken (5 fails), M4 rogue band-reading engine arm (1 fail — first run
  caught a weak pin: forged-band pins asserted action only, so a HOLD arm
  passed; strengthened with hold/hold_text pins, re-killed).
- Line endings + charsets preserved (hunter_guide.lua ASCII CRLF restored
  after an em-dash slip; classes/hunter.lua UTF-8 CRLF; tests ASCII; a
  global ASCII pass that touched 8 pre-existing Sec. citations was reverted).

## Re-verify evidence (2026-10-19, desk weakaura-reverify; recipe: firecrawl_scrape waitFor:8000 + maxAge:0)

- https://wago.io/J3U7jOhMI — SCRAPE-CONFIRMED (MDLEN 3375):
  `Melee weave - Distance approximation`, v1.0.0 TBC-WEAKAURA, by
  [kruffz](https://wago.io/p/kruffz), May 14 2026 [2.5.5 TBC (Test)],
  2 stars, 2186 views, 3 installs, tagged Hunter, "No custom code",
  1/1 screenshots (GIF). Description (page text): "Shows your
  approximate distance from your target relative to the melee/ranged
  threshold. Primarily useful against stationary targets. Colors in
  the custom options. Only works for backpedal method atm." The
  stationary-target + backpedal-only + custom-colors framing
  corroborates the prog spec's model assumptions at page level; the
  per-tick math (`prog += dir * (speed_yds / 7) * delta`, 4.6 flip,
  ±0.7 clamps, lib-flip re-anchor) is still operator-reported, NOT
  page-verified — no Lua leaves the page via scrape.
- https://wago.io/eEJOoHci- — SCRAPE-CONFIRMED (MDLEN 3946): `TBC
  Hunter UI [Anniversary - by React] - Laxx weave Mod`, v1.0.1
  TBC-WEAKAURA, by [laxx](https://wago.io/p/laxx), Jun 16 2026
  [2.5.5 TBC (Test)], 0 stars, 351 views, 0 installs, 2 versions,
  tagged Hunter / Combat Mechanics / Accessibility / Visual, "No
  custom code", 1/3 screenshots. Description: "a modification of
  React's TBC Hunter UI, I've integrated the popular melee range bar
  aura along with a few other small tweaks. Credit goes to React for
  the original group and Kruffz for the melee range aura", linking
  https://wago.io/Mmys_57R_ and https://wago.io/J3U7jOhMI. This is
  the pack `bench/hunter_wa_map_2026-10-19.md` was extracted from
  (via docs/hunter-wa.json, not a live scrape): the map's group name
  reads "Laxx Mod", the live page reads "Laxx weave Mod" — same
  import id `eEJOoHci-`, title drift noted, no content conflict. The
  page confirms the Kruffz distance aura is the "popular melee range
  bar aura" integrated into the hunter pack — the weave_band Dynamic
  mapping's WA-side counterpart, still a separate aura, not a pack
  section.
- Nothing in either page changes the filed/built split above: no
  Lua, no `IsItemInRange`/item-8149/`C_Spell`/CLEU surface, no trap
  machines, no speed/dir probes. C_Spell ruling stands.
