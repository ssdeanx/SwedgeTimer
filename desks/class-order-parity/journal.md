# Class-Order-Parity — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close deep-audit findings F8 and F9 — the copy-paste divergence between the
  six class modules on two orderings: the per-frame class hook (guide vs HUD) and the
  `post_init` UI init order (guide / HUD / practice). One order in all six, pinned per class.
- **Scope:** `classes/hunter.lua`, `classes/paladin.lua`, `classes/warrior.lua`,
  `classes/rogue.lua`, `classes/shaman.lua`, `classes/druid.lua` (hook/init ORDER lines only,
  zero behaviour change) and the matching suites `tests/{hunter,paladin,warrior,rogue,shaman,druid}_state.lua`
  (order pins only). Out of scope: main.lua, diag.lua, compat.lua, hud.lua, bars.lua,
  nextaction_ui.lua, practice_ui.lua, practice/design files, options/config, tests/run.sh,
  TOCs, versions, docs. No git commits. No lint-config changes.
- **Source:** `bench/deep_audit_2026-10-19.md` F8 (line 26) and F9 (line 27).
- **Next step:** pick the majority order (guide-first for F8, guide→HUD→practice for F9),
  apply the two reorderings, pin the order per class in the six suites, prove with the
  harness + luacheck + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — F8 + F9 closed: one hook order, one init order, pinned per class
- **Worked on:** Read `bench/deep_audit_2026-10-19.md` F8/F9 and the six class modules.
  Picked the five-class majority for both findings — per-frame hook **guide → HUD**,
  `post_init` **guide → HUD → practice**. Moved the HUD tick block after the guide tick
  block in `classes/hunter.lua` (F8) and moved the practice init after the HUD init in
  `classes/paladin.lua` (F9); the other four classes were already correct and got only a
  one-line comment recording the shared contract (each site now names the order and the
  audit finding). Added an order-pin section to each of the six suites (+13 checks each,
  13 checks × 6 = 78 new pins): a source-order pin (class source read with the comment
  lines stripped, call sites compared) plus a runtime-order pin (spies on
  `st.nextaction_ui` / `st.hud` / `st.practice_ui` record the calls the class really
  makes). The shaman suite has one shared file-scope sandbox, so it saves and restores
  the three modules around the spies.
- **Current state:** 12 files changed (6 class modules, 6 suites); scope held — no
  main.lua/diag/compat/hud/bars/nextaction_ui/practice_ui/options/run.sh/TOC/version/doc
  edits, no git, no lint-config change. Full harness **40 steps, 0 failed**; the six
  class suites PASS (hunter 1006, paladin 533, warrior 1031, rogue 692, shaman 629,
  druid 615). luacheck **3 warnings / 0 errors** repo-wide; the **12 scoped files are
  0/0**. Line endings preserved (5 CRLF class files + shaman LF; all six suites LF); no
  trailing whitespace introduced.
- **Evidence:** (1) Statement-multiset proof — all twelve `post_init` / `on_bar_update`
  bodies extracted before and after: identical multisets, so no statement was added,
  removed or edited; only the two moved blocks changed order. (2) Module independence —
  nextaction_ui↔hud and practice_ui→hud/nextaction_ui have **0** cross-references; the
  only cross-read nearby is the nil-guarded `hud.lua:748 st.practice_ui.is_active()`.
  (3) Mutation proofs **8/8 killed** on `/tmp/opencode/op-mut` copies, each starting
  from a pristine tree: M1 hunter F8, M2 paladin F9, M3 warrior F8, M4 rogue F8,
  M5 shaman F8, M6 druid F8, M7 druid F9, M8 druid code-line decoy (runtime order
  untouched — only the source pin can catch it, so the source pin is proven live).
- **Crossfire (not mine, filed):** a sibling lane landed the deep-audit F2 fix in
  `main.lua` mid-session; the harness briefly showed `main_init_state.lua` failing 2
  checks. Proven not mine: a full tree copy with all twelve of my files reverted to
  their pristine backups but the sibling's `main.lua` kept still fails the same two
  checks (`/tmp/opencode/op-base`). The sibling closed the fixture at 19:42:54; harness
  green again.
- **Next step:** orchestrator validation (harness owner). Nothing further is owed by this
  desk; the remaining deep-audit findings (F1–F7, F10–F14) belong to other lanes.
  In-client confirmation of the reordered tick/init order stays UNCONFIRMED — it cannot
  be proven offline.

## 2026-10-19 — [signal:done] F8 + F9 closed, 8/8 mutations killed
- 12 scoped files; harness 40 steps / 0 failed; luacheck floor held (my 12 files 0/0).
  Report: `bench/class_order_parity_2026-10-19.md`. Signal:
  `desks/class-order-parity/.signals/2026-10-19T23-44-13Z.json`.
