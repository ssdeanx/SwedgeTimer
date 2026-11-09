# Class mirror removal + namespace guards — 2026-10-20

Desk: `desks/class-mirror`. Scope of the brief: `classes/rogue.lua`,
`classes/hunter.lua`, `tests/wiring_check.lua`, `tests/rogue_state.lua`.

## The brief (orchestrator)

The operator hit a live client crash on the TBC client:

```
LUA_WARNING: SwedgeTimer/SwedgeTimer_TBC.toc:77 Error loading SwedgeTimer/classes/rogue.lua
```

The brief attributed the cause to the **namespace mirror** at the end of
`classes/rogue.lua` (`st.ROGUE = ST.ROGUE`) and the same shape in
`classes/hunter.lua:3320` (`st.HUNTER = ST.HUNTER`) — the HU-7 stopgap from the
namespace-resolution problem, dead weight since the engine was fixed to resolve the
class module from the AceAddon table first. Four build items: remove the mirrors,
prove the engine still finds all six classes without them, add a static guard, add a
client-load guard.

## What changed

| File | Change |
|---|---|
| `classes/rogue.lua` | mirror + its comment block removed (was `:3698`); a short note replaces it, worded like the shaman's (the shaman mirror was already removed by the engine lane). CRLF kept. |
| `classes/hunter.lua` | mirror + its comment block removed (was `:3320`); same note. CRLF kept. |
| `tests/wiring_check.lua` | **check 7** (namespace write guard, static) and **check 8** (class-module load guard + engine resolution, sandbox) added; the suite header now describes the one exception to "never loads the addon sources". |
| `tests/rogue_state.lua` | the pin that asserted the mirror's presence (`eq(sb.st.ROGUE, ST2.ROGUE, ...)`) replaced by the shaman-suite shape: the alias must be absent AND the engine's own accessor must still find the class module. LF kept. |

No behaviour change for any class: the mirror was a second name for a table the engine
already resolves from the AceAddon table (`practice.lua:3421` `H.practice_class_module`
reads the addon object first, the namespace only as a fallback; `practice_ui.lua:629`
resolves `ST[class_key]` first too).

## Check 7 — namespace write guard (static, source scan)

Two invariants, both structural (no behaviour test can see them):

- **7a** a **class module** must not assign to the namespace table at file scope;
- **7b** **no addon file** may put a **class table** on the namespace (`st.<CLASS> = ...`
  / `st["<CLASS>"] = ...`), at any scope — the mirror shape, wherever it comes back
  (a class file, or a "central" one in `main.lua`).

**File-scope detection.** A line is *load-time* (file scope) when it is not inside a
function body. The scanner tracks FUNCTION depth separately from block depth (a
statement inside a top-level `if` still runs at load time), counts
`function/if/for/while/repeat` as openers and `end/until` as closers, and treats the
`do` of a `for`/`while` header as belonging to its header (a bare `do` block opens one).
It was **cross-checked against the compiler's own answer** (`luac5.1 -l -l`: the main
chunk's line set = the file-scope statements) over every addon file: **zero missed and
zero invented file-scope namespace assignments** (`/tmp/opencode/nsprobe/xcheck3.lua`).
String contents are blanked first, so a keyword inside a literal cannot fool it.

**Non-vacuity.** The scan must demonstrably still see file-scope namespace writes, so
the root modules' bootstrap writes are counted and floor-pinned: **326 file-scope
namespace writes across 30 root modules** (floor 100).

**Deviation from the brief, stated plainly.** The brief asked for "any addon file
assigns to the namespace table at file scope" to fail. That cannot be applied
literally: the addon's own house idiom publishes every module's table into the
namespace at file scope (`st.<module> = st.<module> or {}`), **326 writes in 30 root
modules** — and those files load on the operator's client. They are therefore
**reported and counted, not failed**; what is banned is a *class module* touching the
namespace at load time (7a) and a *class table* on the namespace at all (7b). The
operator may rule otherwise; the count is printed on every run so the change is
visible.

## Check 8 — class-module load guard + engine resolution (sandbox)

The offline class suites already load every class module, but into a sandbox whose
namespace table is a **plain table**, which hides a namespace write. Check 8 loads
each class module in a hermetic sandbox whose namespace is a **proxy that records
every write** (a plain table only records new keys; the proxy records all of them):

- the class module must **load** (a file-scope error is a client load failure) —
  the sandbox needs only `LibStub` (the AceAddon table), `st.api`,
  `st.utils.convert_lookup_table` and the namespace;
- its file scope must **write nothing** to the namespace;
- the shared engine's own accessor (`practice.lua`'s `H.practice_class_module`) must
  find **all six** class modules, each resolving to the addon's own class table, with
  **no namespace mirror anywhere in the tree**.

Current tree: `772 checks, 0 failures, 3 accepted known defect(s), 0 stale accept(s)`
(the 3 accepted are the pre-existing `SWING_TIMER_*` init-guard entries).

## Proofs (mutation copies — the repo tree was never mutated)

Reproduce (the repo tree is never touched; the copies are under `/tmp/opencode`):

```sh
rsync -a --exclude=Media --exclude=docs --exclude=.git /home/sam/SwedgeTimer/ /tmp/opencode/mirror_mut/
printf 'st.ROGUE = ST.ROGUE\r\n' >> /tmp/opencode/mirror_mut/classes/rogue.lua
cd /tmp/opencode/mirror_mut && lua5.1 tests/wiring_check.lua   # -> 4 failures, exit 1
```

`/tmp/opencode/mirror_mut` (one mirror re-added at the end of `classes/rogue.lua`):

```
FAIL classes/rogue.lua:3702 publishes the class table ROGUE onto the addon namespace (st.ROGUE = ...)
FAIL classes/rogue.lua:3702 a class module writes to the addon namespace at file scope (st.ROGUE = ST.ROGUE)
FAIL classes/rogue.lua writes to the addon namespace while it loads (st.ROGUE = ...)
FAIL the addon namespace still carries the ROGUE class table - the mirror is back
--> 773 checks, 4 failures   (exit 1)
```

`/tmp/opencode/mirror_mut2` (three shapes at once: a class-module mirror in
`classes/shaman.lua`, the `classes/hunter.lua` mirror, and a "central" mirror in
`main.lua`): **9 failures, exit 1** — the static guard names every site with
file:line, the load guard fires for both class modules, and the central mirror in a
root module is caught by 7b alone (the load guard only loads the class modules).

```
FAIL main.lua:2091 publishes the class table ROGUE onto the addon namespace (st.ROGUE = ...)
FAIL classes/hunter.lua:5372 publishes the class table HUNTER onto the addon namespace (st.HUNTER = ...)
FAIL classes/shaman.lua:5356 publishes the class table SHAMAN onto the addon namespace (st.SHAMAN = ...)
FAIL classes/hunter.lua:5372 a class module writes to the addon namespace at file scope (st.HUNTER = ST.HUNTER)
FAIL classes/shaman.lua:5356 a class module writes to the addon namespace at file scope (st.SHAMAN = ST.SHAMAN)
FAIL classes/hunter.lua writes to the addon namespace while it loads (st.HUNTER = ...)
FAIL classes/shaman.lua writes to the addon namespace while it loads (st.SHAMAN = ...)
FAIL the addon namespace still carries the HUNTER class table - the mirror is back
FAIL the addon namespace still carries the SHAMAN class table - the mirror is back
--> 775 checks, 9 failures   (exit 1)
```

Full harness on the mutated copy: **43 steps, 1 failed** (`wiring_check`).
Full harness on the repo tree: **43 steps, 0 failed**, luacheck **2 warnings / 0
errors in 85 files** (the floor, unchanged).

Tree census after the change (`/tmp/opencode/nsprobe/`): **no** `st.<CLASS> =`
assignment anywhere in the addon (root or class), and the file-scope namespace writes
are **326 in 30 root modules and 0 in the six class modules**.

## The mechanism — what the evidence actually supports (a disagreement, for the operator)

The brief's stated mechanism is *"writing to the addon's namespace table is not a
supported operation on a real client (the namespace is protected)"*. **The tree and the
reference client source contradict that**, so it is recorded as UNVERIFIED rather than
asserted:

1. The tree's own idiom is a file-scope namespace write: **326 writes in 30 root
   modules** (`compat.lua:99`, `utils.lua:2-3`, `practice.lua:78`,
   `druid_guide.lua:547`, …). Every one of those files loads on the operator's client
   (the client reported exactly one failing file: `classes/rogue.lua`).
2. Blizzard's own addons write to their namespace table at file scope in the reference
   client source (`classic_anniversary`):
   `Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameFiltersSecure.lua:7`
   (`addonTbl.CreateSecureFiltersArray = ...`) and
   `Interface/AddOns/Blizzard_ChatFrameBase/Shared/MacroExecutionManager.lua:13`
   (`addonTbl.MacroEditBox = ...`).
3. The mirror's *shape* is not special: `st.ROGUE = ST.ROGUE` publishes a plain table
   (`main.lua:67` creates `ST.ROGUE = {}`), exactly like `st.api = api`.

What the evidence **does** support: the mirror was the **only** namespace write in any
class module, and every class file is in every TOC, so its file scope runs on every
client — the operator's failure named the last TOC entry, and the two mirrors were the
two class-module offenders. The removal is correct regardless (the engine resolves the
class module from the AceAddon table first), and the guards now make a
file-scope namespace write in a class module a build failure.

**What would close the gap:** the operator's client error text above the
`LUA_WARNING` line (the client's own `.../classes/rogue.lua:<line>: <message>`), or a
re-test in-client after this change. Offline, the crash cause is **UNCONFIRMED**.

## Files changed (nothing else was touched)

- `classes/rogue.lua` (mirror removed, note added) — CRLF preserved
- `classes/hunter.lua` (mirror removed, note added) — CRLF preserved
- `tests/wiring_check.lua` (checks 7 and 8) — LF preserved
- `tests/rogue_state.lua` (the mirror pin moved) — LF preserved

`tests/hunter_state.lua` was **not** touched: it carried no pin asserting the mirror's
presence (grep: no `st.HUNTER` reference), and the hunter mirror is covered by the
guards in `tests/wiring_check.lua`.

No git, no TOC, no version, no CHANGELOG/README/TESTING, no lint-config change.
