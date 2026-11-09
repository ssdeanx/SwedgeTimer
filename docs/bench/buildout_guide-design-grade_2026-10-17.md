# buildout_guide-design-grade — next-action + designer enterprise review (grade round)

Date: 2026-10-17. Desk: guide-design. Brief: `bench/briefs/brief_guide-design-grade_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Changes (writable scope held exactly)

`designmode.lua` (+50 lines, one appended block), `tests/designmode_state.lua` (+fixture opt-in, +2 load pins, +4 no-delegate pins, +1 count true-up, new section 16), `tests/design_state.lua` (+2 static needles), `tests/nextaction_state.lua` (+17 rotation-text resolution pins). No other file touched — `nextaction.lua`, `nextaction_ui.lua`, `design.lua` needed no code change (verified, §2–§3). No git ops. Endings preserved (CRLF addon files, LF tests). `tests/bars_state.lua` untouched per the brief (counts reported in §5).

### designmode.lua — C6 handoff completion: practice rotation + timeline targets
- New `practice_delegate(key)` (lazy lookup into `st.practice_ui.design_targets`, nil-safe) + `practice_descriptor(key, title)` builder, then `register(practice_descriptor("practice_rotation", ...))` and `register(practice_descriptor("practice_timeline", ...))`. Registry: 7 → **9**.
- Delegation semantics: `get_frame`/`available`/`save`/`reset` forward through the practice module's own descriptors via `pcall` (single source; the practice lane owns geometry). With no delegate (old sandboxes, practice absent) the entries degrade silently — `get_frame` nil, `available` false, count stable. No lock seam (matches the panel entry).
- Deliberately NOT registered: bar-relative sidebars (paladin JotC mini-bar container, CD icon group container, enemy swing bar) — all are children of the bar frame and move with the bar overlay; standalone targets would fight their bar-relative anchors. Audit table (§4).

## 2. Rotation-pattern verification (engine untouched)

- `sequences` / `descriptions` / `display_names` for all 8 keys verified identical to the archived `docs/swedge/SwedgeTimer_TBC/rotation.lua:37-70` (key order, step order, `cs_late`/`blood_auto`/`cmd_auto` spellings).
- `calculate_rotation` thresholds + priority order verified identical to the archive (`rotation.lua:140-172`); `get_gcd_duration`/`get_haste_amount` unchanged.
- Twist landmarks (`rel_div`/`rel_gap`/`rel_swing`/`rel_div2`/`rel_gap2`), HOLD/RIDE branches, prediction_hold maths: unchanged, all 426 pre-existing pins green — twist pins not weakened.
- Lust override: `LUST_TWIST_WINDOW_SCALE == 0.6` + `apply_lust_window` passthrough/scale/floor edges already pinned; the C2 family contract is consumed in `classes/paladin.lua` (out of scope) — engine side needs no change.
- New: rotation-text resolution pins — all 8 patterns selected by probe speeds each resolve a non-empty `display_names` entry (+17 checks: 8 select + 8 resolve + 1 coverage-of-8).
- Retail inertness, Era/Forever/FCFS branches: unchanged, all pins green. No `st.is_mainline` gate anywhere in scope (verified by the existing `design_state` pin + `nextaction_ui` header rule).

## 3. Guide frame wiring audit (nextaction_ui.lua — no change, all live)

| Element | Source | Verdict |
|---|---|---|
| 8 slot icons (cs/soc/sob/twist/judge/consecration/exorcism/how) | `provider.slots` → `slot_index`; `out.action` ∈ {soc,sob,twist,cs,nil} (riding→sob), `out.filler_slot` = `filler_kind` ∈ {consecration,exorcism,how,nil}, `out.judge_slot` from `judge_call` — every emitted key names an existing slot | live, no placeholder |
| HOLD/RIDE overlay | `out.hold` + `out.hold_text` (provider maps riding→"RIDE" else "HOLD"); gated on `db.nextaction_hold_enabled ~= false` | live |
| Rotation text | `provider.rotation_key(inputs)` → `provider.rotation_names` map; hidden when nil (Era/Forever/FCFS) or option off | live |
| Cooldown swipes | slots with `cooldown_key` drive per tick: seal slots via `<key>_expires` aura path, CS/Judge via `<key>_remaining/_duration`; `set-once` latch + `swipe_always` split (seals always, CS/Judge only while shown) | live; fillers have no swipe by archive design (`filler_remaining` is engine-consumed) |
| Idle state | `idle_alpha` (sob 0.5), swipes cleared, glow stopped | live |
| Visibility | provider + `nextaction_enabled ~= false` + lock/visibility key + live swing (`ends_at/start/not is_full`) — swing activity decides, never `st.is_mainline` | compliant |
| Per-tick cost | reused `ui.inputs`/`ui.out` tables, prebuilt per-slot key names, throttled compute | no per-frame allocation |

## 4. Target-registry audit table

Registry after this round (9): `bar_mainhand`, `bar_offhand`, `bar_ranged`, `hud`, `rottext`, `nag`, `practice_panel`, **`practice_rotation` (new)**, **`practice_timeline` (new)**. Snap templates: pips `<key>_cells` (unchanged, section-15 pins green); mouse anchoring: unchanged, pins green.

| Widget (shipped this round) | Frame? | Design target | Disposition |
|---|---|---|---|
| Druid pips row | yes (factory frame) | `druid_pips` (dynamic, bars-design C6) | registered by factory — untouched |
| Paladin JotC mini-bar container | yes (`vf.jotc_bar.frame`) | none | moves with the bar overlay (child of bar frame); no standalone target by design |
| Paladin CD icon group container | yes (`vf.cd_icons.frame`) | none | same as JotC — bar-relative, moves with the bar |
| Enemy swing bar | yes (`st.enemy_swing.runtime.frame`) | none | child of mainhand bar frame, moves with the bar (report deferred it here; covered) |
| Practice panel | yes | `practice_panel` | pre-existing — untouched |
| Practice rotation display | yes (`ui.rotation_display`) | `practice_rotation` | **registered this round (delegating)** |
| Practice timeline | yes (`ui.timeline_frame`) | `practice_timeline` | **registered this round (delegating)** |
| Hunter badges, warrior bank/SB/Shout, shaman weave markers/sync, druid trackers/debuffs, paladin twist badge | no (textures/fontstrings on the bar visuals frame) | n/a | not frame targets — correctly unregistered; move with the bar |
| HUD slots, rotation label, guide frame | yes | `hud`, `rottext`, `nag` | pre-existing — untouched |

Half-wiring hunt: no registered target without a frame path (all degrade to nil + skip); no screen-positioned frame without a target (the two found are now registered); no template points at a renamed widget (only pips templates exist, pinned).

## 5. Tests + evidence

- `tests/nextaction_state.lua`: **PASS 443** (was 426; +17 rotation-text resolution).
- `tests/design_state.lua`: **PASS 319** (was 317; +2 needles).
- `tests/designmode_state.lua`: **460 checks, 0 failed** (was 427; +33: section 16 delegation/availability/overlay-count/pool-reuse/drag-save/reset + no-delegate degrade + pips count true-up 8→10).
- `luacheck` on all 7 scope files: **0 warnings / 0 errors** (was already 0; still 0).
- Full `bash tests/run.sh`: **35 steps, 3 failed** — all outside scope: `bars_state.lua` 12 count pins + `hud_state.lua` 4 druid-slot pins (the reconcile wave this brief defers; deltas unchanged from baseline — my round adds **0 frames/textures/fontstrings at load**: the two registry entries are plain tables) and `toc_check.lua` 1 failure (`SwedgeTimer.toc` Interface now reads 120105 vs the check's 120100 — a cross-lane toc edit that landed mid-run; this desk never touches tocs).
- Mutation proofs (`/tmp/opencode/mut_guide-design/`, restores `cmp`-identical): (1) delegation `return t` → `return nil`: **11 FAILs** (section-16 resolve/available/overlay/save counts). (2) `display_names["2/3"]` blanked: **2 FAILs** (the pre-existing name pin + the new resolution pin). Both restored → all suites green.

## 6. UNCONFIRMED / in-client checklist

- Overlay drag feel, guide-line density with 8 session overlays, and mouse-anchored drops on the two new targets — offline maths only.
- Guide icon textures (Era Righteousness slot, Wrath DS slot, HoW/HW filler slot), swipe rendering, glow, rotation-text font — pixels need a client.
- Lust 0.6 window, JotC refresh cadence, racial CD ids — paladin lane items, still open.
- Enemy-swing and paladin sidebars move with the bar overlay — confirm the assembly feels right in-client before any standalone-target request.
- No git operations performed; the tree is left with all changes in place and stated.
