# Class order parity — F8 + F9 (deep-audit 2026-10-19)

Desk `class-order-parity`. Closes the two copy-paste divergences the deep audit found
between the six class modules (`bench/deep_audit_2026-10-19.md` F8 line 26, F9 line 27).

**VERDICT: CLOSED** — one hook order and one init order in all six classes, pinned per class.

---

## What was chosen, and why

| Finding | Before | After (all six) | Why this order |
|---|---|---|---|
| **F8** per-frame class hook | hunter ran HUD → guide; the other five ran guide → HUD | **guide → HUD** | the five-class majority. The guide is the advisory surface (it renders the next action); the HUD is the cooldown surface (it renders timers). Rendering the advice first means the frame the player reads for "what do I press" is the one computed from the freshest swing state. |
| **F9** `post_init` UI init | paladin ran guide → practice → HUD; the other five ran guide → HUD → practice | **guide → HUD → practice** | the five-class majority. The practice surface is a session panel the player opens by hand; it is the last thing built, so nothing can be handed a half-built HUD when the session starts. |

Both choices are the five-class majority, so four classes (warrior, rogue, shaman, druid)
needed **no code movement at all** — only a comment recording the shared contract.

## Files changed (12; scope held)

Six class modules (order lines only, zero behaviour change):

| File | Change |
|---|---|
| `classes/hunter.lua` | **F8 moved**: the HUD tick block now runs *after* the guide tick block. F9 comment added. |
| `classes/paladin.lua` | **F9 moved**: the practice init now runs *after* the HUD init. F8 comment added. |
| `classes/warrior.lua` | comments only (F8 + F9 contract recorded). |
| `classes/rogue.lua` | comments only (F8 + F9 contract recorded). |
| `classes/shaman.lua` | comments only (F8 + F9 contract recorded). |
| `classes/druid.lua` | comments only (F8 + F9 contract recorded). |

Six matching suites (order pins only):

| File | Section | Checks |
|---|---|---|
| `tests/hunter_state.lua` | 24) Shared class order | 993 → 1006 (+13) |
| `tests/paladin_state.lua` | 22) Shared class order | 520 → 533 (+13) |
| `tests/warrior_state.lua` | 34) Shared class order | 1018 → 1031 (+13) |
| `tests/rogue_state.lua` | 20) Shared class order | 679 → 692 (+13) |
| `tests/shaman_state.lua` | 37) Shared class order | 616 → 629 (+13) |
| `tests/druid_state.lua` | 36) Shared class order | 602 → 615 (+13) |

Nothing else was touched: `main.lua`, `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`,
`nextaction_ui.lua`, `practice_ui.lua`, the practice/design files, options/config,
`tests/run.sh`, the TOCs, versions and docs are untouched. No git commands were run.

## The pin (13 checks per class suite)

Each suite pins the order **twice, independently**:

1. **Source order** — the class source is read with the comment lines stripped (a call
   quoted inside a comment must not be read as the call), then the call sites are
   located and compared: `st.nextaction_ui.on_bar_update(self, hand)` before
   `st.hud.on_bar_update(self, hand)`; `st.nextaction_ui.init(self)` before
   `st.hud.init(self)` before `st.practice_ui.init(self)`.
2. **Runtime order** — spies replace `st.nextaction_ui` / `st.hud` / `st.practice_ui` and
   record the calls the class actually makes: `post_init` must build guide → HUD →
   practice, and the per-frame hook must tick the guide before the HUD.

The shaman suite runs on one shared file-scope sandbox, so it saves and restores the
three modules around the spies; the other five use a fresh `build()` sandbox.

## Proof of zero behaviour change

**1. Statement-multiset proof.** Every `post_init` and `on_bar_update` body of the six
classes was extracted before and after (comments and blanks dropped, whitespace
normalised) and compared as multisets:

```
hunter   post_init      19->19  multiset-identical=True  order-identical=True
hunter   on_bar_update  31->31  multiset-identical=True  order-identical=False   <- F8 moved
paladin  post_init      45->45  multiset-identical=True  order-identical=False   <- F9 moved
paladin  on_bar_update 208->208 multiset-identical=True  order-identical=True
warrior  post_init      43->43  multiset-identical=True  order-identical=True
warrior  on_bar_update  41->41  multiset-identical=True  order-identical=True
rogue    post_init      13->13  multiset-identical=True  order-identical=True
rogue    on_bar_update  28->28  multiset-identical=True  order-identical=True
shaman   post_init      59->59  multiset-identical=True  order-identical=True
shaman   on_bar_update 135->135 multiset-identical=True  order-identical=True
druid    post_init      33->33  multiset-identical=True  order-identical=True
druid    on_bar_update  62->62  multiset-identical=True  order-identical=True
```

No statement was added, removed or edited anywhere; only the order of the two moved
blocks changed, and only in the two functions that needed it.

**2. Module-independence proof.** The three surfaces never read each other:

```
nextaction_ui.lua -> st.hud        : 0 references
hud.lua           -> nextaction_ui : 0 references
practice_ui.lua   -> st.hud / st.nextaction_ui : 0 references
```

The only cross-read in the neighbourhood is `hud.lua:748`
(`if st.practice_ui and st.practice_ui.is_active() then`) — a nil-guarded, read-only probe
of session state that neither reordered call produces. `practice_ui.lua` reads
`st.nextaction` (the pure rotation engine), a different module from `st.nextaction_ui`.

**3. Harness.** Full harness: **40 steps, 0 failed**. The six class suites all PASS.
luacheck: **3 warnings / 0 errors in 80 files**; the 12 scoped files are
**0 warnings / 0 errors** (`luacheck classes/*.lua tests/{six}_state.lua` → 0/0).

## Mutation proofs (8/8 killed)

Disposable copies under `/tmp/opencode/op-mut`; each mutation must make its suite FAIL.

| # | Mutation | Killed by |
|---|---|---|
| M1 | hunter: HUD tick moved back before the guide tick | `order: the guide tick comes before the HUD tick` |
| M2 | paladin: practice init moved back before the HUD init | `order: post_init builds the guide, then the HUD, then the practice surface` |
| M3 | warrior: HUD tick moved back before the guide tick | `order: the guide tick comes before the HUD tick` |
| M4 | rogue: HUD tick moved back before the guide tick | `order: the guide tick comes before the HUD tick` |
| M5 | shaman: HUD tick moved back before the guide tick | `order: the guide tick comes before the HUD tick` |
| M6 | druid: HUD tick moved back before the guide tick | `order: the guide tick comes before the HUD tick` |
| M7 | druid: practice init moved back before the HUD init | `order: post_init builds the guide, then the HUD, then the practice surface` |
| M8 | druid: a **code** line quoting `st.hud.init(self)` planted before the guide init (runtime order untouched) | `order: post_init builds the guide, then the HUD, then the practice surface` — proves the source pin is live on its own, not just mirroring the runtime pin |

Every mutation started from a pristine copy of the tree (a mutation must not inherit the
previous mutation's damage).

## Line endings / whitespace

Preserved exactly, verified per file with `file`:

- `classes/hunter.lua`, `classes/paladin.lua`, `classes/warrior.lua`, `classes/rogue.lua`,
  `classes/druid.lua` — CRLF (unchanged); `classes/shaman.lua` — LF (unchanged).
- all six `tests/*_state.lua` — LF (unchanged).
- No trailing whitespace introduced (`grep -c "[ \t]$"` → 0 in all six class files);
  the inserted comment lines are wrapped to the file's own comment width and use each
  file's own indentation (spaces in hunter/paladin/warrior/druid, tabs in rogue/shaman).

## Crossfire observed (not mine, filed for the orchestrator)

While this lane was running, a sibling lane landed the deep-audit **F2** fix in `main.lua`
(mtime 19:39:41, later 19:42:59) and updated `tests/main_init_state.lua`. In between, the
harness showed `main_init_state.lua` failing 2 checks ("the offhand recolour runs
post-init", "the offhand timer is snapped to now minus speed").

**This was proven not to be mine**: a full copy of the tree with all six class files and
all six class suites reverted to their pristine backups, but the sibling's `main.lua` kept,
still fails the same two checks (`/tmp/opencode/op-base`). The sibling finished the
fixture at 19:42:54; the harness is green again.

## Limitations (stated by the desk)

1. **Verified offline only.** No in-client load was performed; the reorder is proven
   equivalent offline (statement multisets + module independence), not in a game client.
2. The suite pin reads the class **source** for the source-order half. It is proven
   non-vacuous by M8, but it is a text pin, not a semantic one — a future edit that moves
   a call into a helper function would need the pin updated (the runtime half still
   catches a real reorder).
3. The paladin's `post_init` keeps the `LCD.Register` block between the guide init and the
   HUD init (it is paladin-only and untouched by F9); the pinned relative order is
   guide → HUD → practice, which holds.
