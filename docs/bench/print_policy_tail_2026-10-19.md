# print-policy tail — main.lua + config_presets.lua (2026-10-19)

Desk `print-policy-tail`. Scope: `main.lua`, `config_presets.lua`, and the pins in
`tests/main_init_state.lua` / `tests/options_load_state.lua`.
Verdict: **F12 family closed for the two files this lane owns — no bare-global `print`
left in either; `config.lua` filed for its owning lane.**

Follow-on to `bench/bars_print_policy_2026-10-19.md` (desk `bars-print-policy`), whose
§4 listed the two remaining sites outside `bars.lua`.

---

## 1. The premise, re-verified against the source

`bench/bars_print_policy_2026-10-19.md:92-94` filed three sites outside `bars.lua`:

| Site | Shape | This lane |
|---|---|---|
| `config.lua:74` (now **line 82** — the file was edited by a running lane after the bars lane filed it) | live bare global `print` under `st.debug` | **FILED, NOT TOUCHED** (owned by a running lane — see §5) |
| `config_presets.lua:1393` | live bare global `print` under `st.debug` | **FIXED** |
| `main.lua:50` + `main.lua:1893` | `local print = st.utils.print_msg` alias | **FIXED** |

Both sites this lane owns were re-read before the edit, and the finding held:

* **`main.lua:50`** really did bind the alias `local print = st.utils.print_msg`, and
  its only live use was the module-parse trailer at the end of the file. So the *output*
  was already chat output — the *identifier* was the readability trap, exactly as the
  bars lane found for `bars.lua`.
* **`config_presets.lua:1393`** was a genuine bare global `print` under the same
  `st.debug` gate. `config_presets.lua` has **no** `print` alias (unlike `config.lua`,
  which had a *commented-out* one at line 9), so this was the raw client global.

Load order was re-checked for both (the alias at `main.lua:50` executes at load time, so
`st.utils.print_msg` must already exist): `utils.lua` is TOC line 37/38 and
`config_presets.lua` 64/65, `main.lua` 55/56 in **all 7 tocs** — `st.utils.print_msg` is
defined (`utils.lua:6`) before both files load. No ordering hazard.

## 2. What changed (4 files, this lane's scope only)

### `main.lua` (CRLF preserved, 1900 CR bytes before and after)

| Line (post) | Change |
|---|---|
| 50-54 | `local print = st.utils.print_msg` **removed**; replaced by the file's chat-output policy note, worded for this file (it names `st.utils.print_msg` *and* `ST:Print`/AceConsole, which this file also uses). The identifier `print` is gone from the live code. |
| 844-850, 961, 1018, 1049, 1056, 1614, 1622-1623, 1767 | The **nine** commented-out debug prints now name `st.utils.print_msg(...)`. Inert either way, but with the alias gone they would have reached the raw global if re-enabled; this keeps their latent intent identical — the same call the bars lane made on `bars.lua`. |
| 1900 | `if st.debug then print('-- Parsed main1.lua module correctly') end` → `if st.debug then st.utils.print_msg('-- Parsed main1.lua module correctly') end` — **the live fix**. Same function, same message, no behaviour change. The `st.debug` gate is untouched. |

The message text is byte-identical (including the historical `main1.lua` spelling) so
the chat output is unchanged when the switch is flipped.

### `config_presets.lua` (LF preserved, 0 CR bytes before and after)

| Line | Change |
|---|---|
| 1393 | `if st.debug then print('-- Parsed config_presets.lua module correctly') end` → `if st.debug then st.utils.print_msg('-- Parsed config_presets.lua module correctly') end` — **the live fix**. Same function, same message. The `st.debug` gate is untouched. |

### `tests/main_init_state.lua` (LF preserved) — new **section 18) Output policy**

The sandbox gained two pieces of instrumentation:

* `sb.raw_prints` + `env.print` — a spy on the **client's global print**. The sandbox
  has no global print of its own, so a module that reaches the global is now an
  assertion instead of stray console output (mirrors the bars lane's `bars_state.lua`
  fixture).
* `opts.debug` — flips `st.debug = true` **after** `utils.lua` has loaded (so
  `utils.lua`'s own trailer stays silent) but **before** `main.lua` loads. Without it the
  `st.debug`-gated trailer is unreachable and the runtime pin would be vacuous.

4 new checks (764 → **768 checks**):

1. **source scan** — `main.lua` contains no bare `print(` call anywhere (live code *and*
   comments; `st.utils.print_msg(` never contains the token `print(`).
2. **alias pin** — `main.lua` defines no `local print =` alias.
3. **global-print spy** — the client's global print is never called by `main.lua`.
4. **chat-frame report** — with `st.debug` on, the module trailer arrives through
   `DEFAULT_CHAT_FRAME:AddMessage`.

### `tests/options_load_state.lua` (LF preserved) — new **section 21) Output policy**

This suite owns the config-file pins (its existing section 7 already reads
`config_presets.lua` and pins `option_tables.lua`'s missing alias), so the
`config_presets.lua` half of the lane landed here.

4 new checks (**3252 → 3256 checks**):

1. **source scan** — `config_presets.lua` contains no bare `print(` call anywhere.
2. **alias pin** — `config_presets.lua` defines no `local print =` alias.
3. **global-print spy** — the client's global print is never called by
   `config_presets.lua`.
4. **chat-frame report** — with `st.debug` on, the module trailer arrives through
   `DEFAULT_CHAT_FRAME:AddMessage`.

The runtime half of this section uses a **dedicated** sandbox rather than the suite's
shared `load_modules()`: the shared loader also pulls in `config.lua`, which is still on
the old path (§5). Loading `config.lua` in the measurement would have made this lane's
verdict depend on another lane's file.

## 3. Audit sweep of the rest of the two files — KEEP with rationale

| Site | Verdict | Rationale |
|---|---|---|
| `main.lua` `self:Print(...)` (×14: version banner, range-offline notice, unknown-hand notices, callback isolation report, `/st` usage line, …) | KEEP | AceConsole's `Print` → `DEFAULT_CHAT_FRAME:AddMessage` (`Libs/AceConsole-3.0/AceConsole-3.0.lua:54`). It is the addon's second, established chat path, used identically by `bars.lua`, `hud.lua`, `nextaction_ui.lua`, `practice_ui.lua` and `designmode.lua`. It never touches a raw global. |
| `main.lua:1782` `function ST:print_runtime_diag()` | KEEP | A method *name*, not a call. Its body writes to `self:Print(...)` (`main.lua:1809/1814`), the AceConsole path above. |
| `main.lua:1781` / `1836` prose mentioning "print" | KEEP | Comments describing the diag report. |
| `config_presets.lua` — no other print reference | KEEP | The file's only output path was the trailer. |

## 4. Validation

* `bash tests/run.sh` (in-tree, final tree): **41 steps, 0 failed** for this lane's
  scope — `tests/main_init_state.lua` **768 checks, 0 failed** and
  `tests/options_load_state.lua` **3280 checks, 0 failed**. The full-harness run is
  subject to a concurrent lane landing `classes/*.lua` / `practice_ui.lua` mid-run; see
  §6 for the proof that the failures it produced are not this lane's.
* `luacheck .`: **2 warnings / 0 errors in 82 files** — the ledger floor, held. The two
  warnings are `compat.lua:36` (unused `addon_name`) and `main.lua:81` (`table.pack`);
  both pre-existing and both in sibling-lane files. `main.lua`'s warning moved from
  line 77 to 81 only because this lane's policy note added four comment lines above it.
* `luacheck main.lua config_presets.lua tests/main_init_state.lua tests/options_load_state.lua`:
  **1 warning / 0 errors in 4 files** — the `table.pack` one, pre-existing.
* Mutation proofs on `/tmp/opencode` copies (`/tmp/opencode/mut_print.py`, base
  `/tmp/opencode/mut_print_base`, runner copies into `/tmp/opencode/mut_print_work`):
  **7/7 killed**.
  Reproduce from the repo root:
  `rm -rf /tmp/opencode/mut_print_base && mkdir -p /tmp/opencode/mut_print_base && tar -cf - --exclude=.git . | (cd /tmp/opencode/mut_print_base && tar -xf -) && python3 /tmp/opencode/mut_print.py`
  * M1 alias returns to `main.lua` + trailer routed through it → killed by 2 pins
    (source scan, alias pin).
  * M2 `main.lua` trailer → raw global `print` → killed by 3 pins (source scan,
    global-print spy, chat-frame report).
  * M3 a **commented-out** debug line back to `print(...)` → killed by the source scan.
  * M4 `main.lua` trailer removed → killed by the chat-frame report pin.
  * M5 `config_presets.lua` trailer → raw global `print` → killed by 3 pins (source
    scan, global-print spy, chat-frame report).
  * M6 alias returns to `config_presets.lua` + trailer routed through it → killed by 2
    pins (source scan, alias pin).
  * M7 `config_presets.lua` trailer removed → killed by the chat-frame report pin.
  * Every mutant was checked to fail **for the stated reason** (the FAIL lines name the
    output-policy pin), not from an unrelated load error.
  * End-to-end: the full `tests/run.sh` on the M2 copy reports **41 steps, 1 failed**
    (`main_init_state.lua` only); on the M5 copy **41 steps, 1 failed**
    (`options_load_state.lua` only). The base copy is **41 steps, 0 failed**, so each
    mutant is the sole cause of its failure.

## 5. Filed for the owning lane — NOT touched

* **`config.lua:82`** (the bars lane filed it as line 74; a running lane has since edited
  the file above it) — `if st.debug then print('-- Parsed config.lua module correctly') end`.
  A live bare global `print`; `config.lua` has no `print` alias (its alias at line 9 is
  commented out), so it would reach the client's global if `st.debug` were ever flipped.
  **Out of this lane's scope** (a running lane owns `config.lua`) — recorded here and in
  the desk journal for that lane to pick up. It is a one-line change of exactly the same
  shape as `config_presets.lua:1393`.

## 6. Notes

* No git, no lint-config change, no TOC/version/docs/options/config change.
* Line endings verified per file before editing (`file` + CR-byte count), not assumed:
  `main.lua` is CRLF (1900 CR bytes before and after), `config_presets.lua` is LF (0 CR
  bytes before and after), both test suites are LF.
* The `st.debug` gate is intact on both trailers, so there is **no default-visible
  change**: with `st.debug = false` (the shipped value, `utils.lua:65`) neither line
  runs, exactly as before.
* The two `st.debug` trailers are the only callers of `st.utils.print_msg` in these two
  files, so no other call site's output changed.
* The tree was **moving under this lane** during the session (a concurrent lane was
  landing `classes/*.lua`, `practice_ui.lua` and `tests/practice_state.lua` /
  `tests/practice_ui_state.lua` throughout; the `luacheck` file count went 80 → 82 and
  the warning count fluctuated between 2, 5, 6 and 7 across consecutive runs before
  settling at **2 / 0 in 82 files**). Harness failures in `tests/hunter_state.lua`,
  `tests/hunter_guide_state.lua`, `tests/druid_state.lua`, `tests/practice_ui_state.lua`,
  `tests/paladin_state.lua`, `tests/wiring_check.lua` and the `luac5.1 -p` step appeared
  and disappeared between runs, and the failing suite changed every run — the signature
  of files being rewritten mid-run, not of a stable defect.
  **Proof that none of it is this lane's:** the lane's own edits were reverted
  programmatically in a copy of the *current* tree (`/tmp/opencode/revert_lane.py`
  reverses the exact `main.lua` + `config_presets.lua` hunks) and the harness re-run.
  `tests/hunter_guide_state.lua` failed **identically** in that reverted copy
  (`pop: the pops are a TBC rotation (got S, want nil)`), while
  `tests/main_init_state.lua` and `tests/options_load_state.lua` failed **only** in the
  reverted copy — i.e. this lane's pins correctly catch its own edits and nothing else.
  The two owning suites are green in the tree, and `luacheck` on this lane's four files
  reports **1 warning / 0 errors** — the pre-existing `table.pack` one that is present
  in `HEAD` as well.
* Every validation number above was taken from the **final** tree, and the mutation base
  was rebuilt (including `bench/`, which the first build had excluded) so the base copy
  itself is 41/0 green.
