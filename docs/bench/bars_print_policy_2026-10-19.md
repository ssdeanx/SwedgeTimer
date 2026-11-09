# bars.lua output policy — F12 lane (2026-10-19)

Desk `bars-print-policy`. Scope: `bars.lua` + `tests/bars_state.lua` (pins only).
Verdict: **F12 FIXED (premise corrected) + 2 audit-sweep fixes + 4 KEEP-with-rationale.**

The finding under repair: `bench/deep_audit_2026-10-19.md:30` — *"F12 | LOW | bars.lua:1185 |
Raw global `print` in a live error path (not pcall-wrapped) — inconsistent with the addon's
chat-output policy and would throw on a client without `print`. | Use `st.utils.print_msg`."*

---

## 1. The finding's premise, re-verified against the source

**The location claim was wrong: `bars.lua:1185` was never the raw global print.**

Before this lane, `bars.lua:13` read

```lua
local print = st.utils.print_msg
```

so the `print(...)` at the error path resolved to the addon's own chat function. The
auditor's own Limitations section lists *global `print`* as `UNVERIFIED-HERE`
(`bench/deep_audit_2026-10-19.md:99`) — the finding was filed without that
re-verification, and the file-local alias is exactly what a source-only reading misses.

Two more facts were checked before the finding was accepted or rejected:

* **Load order.** `utils.lua` is TOC line 37/38 and `bars.lua` line 56/57 in **all 7 tocs**,
  so `st.utils.print_msg` was defined when `bars.lua:13` bound the alias — the alias was
  never nil and the call never threw.
* **Sibling convention.** Every sibling design-mode message already names the chat path
  explicitly: `designmode.lua:575`, `designmode.lua:887`, `designmode.lua:892` all call
  `st.utils.print_msg("Design mode: ...")`, and `bars.lua:1224` (the module's own parse
  line) already used `st.utils.print_msg(...)`.

So the *policy gap* behind F12 was real even though the *mechanism* was not: `bars.lua:1185`
was the only **live** (non-debug) call in the whole live tree that reached the chat path
through an identifier a reader cannot disambiguate — which is exactly why the finding
mis-read it. The fix removes the ambiguity; the chat output is byte-identical.

## 2. What changed (2 files, this lane's scope only)

`bars.lua` (LF preserved, 0 CR bytes before and after):

| Line (post) | Change |
|---|---|
| 13-16 | `local print = st.utils.print_msg` **removed** (it had no remaining user) and replaced by the file's chat-output policy note. A bare `print` call in this file can no longer reach the client's raw global, and the identifier is gone from the live code. |
| 669, 769, 808-809, 849, 998 | The six commented-out debug prints now name `st.utils.print_msg(...)`. They are inert, but with the alias gone they would have reached the raw global if re-enabled; this keeps their latent intent identical. |
| 1191 | `print("Design mode: pips element not registered - " .. tostring(err))` → `st.utils.print_msg(...)` — **the F12 fix**. Same function, same message, no behaviour change. |
| 1200-1204 | **Audit-sweep fix.** `get_cells` now returns nil when `row_boxes` produced no cells (degenerate `size <= 0`), the template's documented "not readable" contract. Before, it indexed a nil table. `designmode.lua:349` pcalls `get_cells`, so the old path was a swallowed Lua error inside the drag handler, not a crash. Latent: no production caller passes `size <= 0` today (`classes/druid.lua:1277` passes no size). |
| 698-702 | **Audit-sweep fix.** The LibDataBroker feed is now isolated through the module's own per-tick guard: `run_guarded(self, "ldb:update", st.ldb.update, self, hand)`. It was the only unprotected call left in `onupdate_common`; a throwing broker feed escaped the tick instead of costing the feed. The bar is painted before this line, so the tick's visible result is unchanged. |

`tests/bars_state.lua` (LF preserved) — new **section 7) Output policy and error isolation**,
8 new checks (838 → **855 checks**), plus one fixture line: the sandbox now spies the
client's global `print` (`env.print` → `sb.raw_prints`), so a module that reaches the
global is an assertion instead of a crash.

1. **source scan** — `bars.lua` contains no bare `print` call anywhere (live code *and*
   comments: `st.utils.print_msg(` never contains the token `print(`).
2. **the client's global print is never called** by the module (the spy stays empty).
3. **a refused design-mode element registration is reported through the chat frame**
   (`DEFAULT_CHAT_FRAME:AddMessage` via `st.utils.print_msg`), with the registry's error
   text in the message.
4. **a degenerate pips row still builds and still registers its template** (no default
   -visible change).
5. **the degenerate pips template degrades instead of raising** — `get_cells` returns nil.
6. **a throwing LibDataBroker feed does not escape the bar tick.**
7. **the throwing feed is counted at its own isolation site** (`bar_hook_errors.by_site
   ["ldb:update"] == 1`).

## 3. Audit sweep of the rest of `bars.lua` — KEEP with rationale

| Site | Verdict | Rationale |
|---|---|---|
| `bars.lua:534,538` `self:Print(...)` (the `run_guarded` reports) | KEEP | AceConsole's `Print` → `DEFAULT_CHAT_FRAME:AddMessage` (`Libs/AceConsole-3.0/AceConsole-3.0.lua:54`). It is the addon's second, established chat path, used identically by `main.lua`, `hud.lua`, `nextaction_ui.lua`, `practice_ui.lua`, `rotationtext.lua` and `designmode.lua`. It never touches a raw global. |
| `bars.lua:1234` `st.utils.print_msg('-- Parsed bars.lua module correctly')` | KEEP | Explicit chat path, `st.debug`-gated (false). |
| `bars.lua:517-541` `run_guarded` for the class hook and the zones | KEEP | The module's per-tick isolation contract (H2); already correct. |
| `bars.lua:1198` `dm.register_template({...})` | KEEP | `designmode.lua:884-900` validates the template and reports its own failures through `st.utils.print_msg`; `designmode.lua` is a sibling lane's file. |
| `bars.lua:1070-1121` the pips factory body (`CreateFrame`, `SetSize`, `CreateTexture`, `convert_color`) | KEEP | The only production caller wraps the whole factory in a pcall (`classes/druid.lua:1160`), and the factory's own contract is nil-safe (`opts` optional, `set()` coerces). |

## 4. Out of scope — observed, NOT touched (routing for the orchestrator)

These are in files owned by sibling lanes. They are **not** this lane's findings to fix,
but they belong in the same family as F12:

* `config.lua:74` — `if st.debug then print('-- Parsed config.lua module correctly') end`
  — a **live bare global print** (`config.lua` has no `print` alias). `st.debug` is false
  (`utils.lua:65`), so it never runs; it would reach the client's global if the switch
  were ever flipped.
* `config_presets.lua:1393` — the same shape.
* `main.lua:50` + `main.lua:1893` — the same `local print = st.utils.print_msg` alias
  shape this lane removed from `bars.lua`; its only live use is the debug parse line, so
  it routes to the chat path correctly, but the identifier is the same readability trap.

## 5. Validation

* `bash tests/run.sh` (in-tree, final tree): **40 steps, 0 failed**.
* `luacheck .`: **2 warnings / 0 errors in 80 files** — the ledger floor, held.
  `luacheck bars.lua tests/bars_state.lua`: **0 warnings / 0 errors**. All three
  warnings seen mid-lane (`compat.lua:36`, `main.lua:77`, `tests/main_init_state.lua:1761`)
  were in sibling-lane files; the third was fixed by its owner during this lane and the
  count returned to 2. This lane neither added nor removed a warning.
* Mutation proofs on `/tmp/opencode` copies (`/tmp/opencode/mut_f12.py`, base copy
  `/tmp/opencode/mut_f12_base`, runner `/tmp/opencode/mut_check`): **5/5 killed**.
  Reproduce from the repo root:
  `rm -rf /tmp/opencode/mut_f12_base && mkdir -p /tmp/opencode/mut_f12_base && tar -cf - --exclude=.git . | (cd /tmp/opencode/mut_f12_base && tar -xf -) && python3 /tmp/opencode/mut_f12.py`
  (the script copies the base per mutation, mutates `bars.lua`, and runs
  `lua5.1 tests/bars_state.lua` against the copy).
  * M1 bare global print at the design-registration error path → killed by 3 independent
    pins (source scan, global-print spy, chat-frame report).
  * M2 local `print` alias + a call through it → killed by the source scan.
  * M3 the refused registration stops being reported → killed by the chat-frame pin.
  * M4 the degenerate-geometry guard removed → killed by the degrade pin.
  * M5 the LibDataBroker feed no longer isolated → killed by the tick-isolation pin.
  * End-to-end: the full `tests/run.sh` on the M1 copy reports **40 steps, 1 failed**.

## 6. Notes

* No git, no lint-config change, no TOC/version/docs/options/config change.
* Line endings verified per file before editing (`file` + CR-byte count), not assumed:
  `bars.lua` and `tests/bars_state.lua` are LF; `utils.lua` and `main.lua` are CRLF and
  were not touched.
* The sibling-lane files listed in §4 were observed, not edited. If the operator wants the
  `st.debug` global prints in `config.lua` / `config_presets.lua` brought onto the chat
  path too, that is a one-line change per file in the config lane.
