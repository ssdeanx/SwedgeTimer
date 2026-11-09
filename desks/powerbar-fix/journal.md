# powerbar-fix — Journal

## 2026-11-06 — desk opened: primary power bar blocked on WoW Forever

- **Purpose:** fix the primary power bar not showing on WoW Forever (Camelot 1.60.1 /
  Interface 16001). Operator: "power bar is being blocked becuz its secret ... i'm pretty
  sure u need to pass the secret data through for it to work."
- **Scope (exact):** `power_bar.lua`, `compat.lua`, `diag.lua` (power line only),
  `tests/power_bar_state.lua`, `tests/forever_secret_compat_state.lua`,
  `desks/powerbar-fix/**`, one NEW bench report. Not mine: `main.lua`, `bars.lua`,
  `hunter_ui.lua`, `weave_range.lua`, TOCs/README/CHANGELOG, `tests/run.sh`, other desks'
  files.
- **Priors read:** `desks/journal.md` (2026-11-06 dispatch), `bench/lessons.md`,
  `AGENTS.md`, `desks/forever-secrets/journal.md` (the aura/cooldown secret work whose
  `is_secret` helper and sandbox style this desk reuses), plus the four lane skills.
- **Next step:** write the red tests, then the additive raw reader and the StatusBar fill.

## 2026-11-06 — fixed, mutation-proven; in-client check owed to the operator

- **Worked on:**
  - **Root cause (verified on origin/forever):** `UnitPower`/`UnitPowerMax` are
    `SecretWhenUnitPowerRestricted`/`SecretWhenUnitPowerMaxRestricted`
    (`UnitDocumentation.lua:2732-2747`, `:2801-2824`); `UnitPowerType` is not secret
    (`:2859-2878`). The old `compat.lua` wrappers nil'd a restricted read (correct for the
    arithmetic consumers in `classes/*.lua`) and the old texture-width `power_bar.lua`
    required numbers, so a restricted tick hid the bar with `why=no-value`. A `StatusBar`
    is the documented sink for the raw value: `SetMinMaxValues`/`SetValue` are
    `SecretArguments="AllowedWhenTainted"` with the `BarValue` aspect
    (`SimpleStatusBarAPIDocumentation.lua:229-236`, `:354-361`), and Blizzard's
    `UnitFrameManaBar_Update` feeds the raw pair straight in
    (`Blizzard_UnitFrame/Mainline/UnitFrame.lua:943-975`).
  - **compat.lua:** additive `api.GetPlayerPower(power_type)` → raw `value`,
    `max_value`, `restricted` (`is_secret(value) or is_secret(max_value)`; `false` on
    classic clients; `nil,nil,false` when `UnitPower` is absent). `api.UnitPower`/
    `api.UnitPowerMax` and `api.UnitPowerType` unchanged.
  - **power_bar.lua:** the fill is now `CreateFrame("StatusBar", ...)` (1 px inset kept via
    `pb.fill_dimensions`, so the painted pixels match the old `SetWidth` maths); a
    restricted state is passed raw to `SetMinMaxValues`/`SetValue`, never compared,
    divided or formatted; the label becomes the constant `"?"` (or hides with the text
    option); `pb.resolve`/`pb.last_state`/`pb.update` carry `restricted` and paint the
    bar. Readable rendering (text/fraction/colours) is unchanged and pinned.
  - **diag.lua:** the verbose power line reads the raw reader and renders
    `value=restricted fraction=?` without `tostring`/division; the legacy pair fallback
    keeps the old line byte-identical.
  - **Tests:** `tests/power_bar_state.lua` gained the StatusBar sandbox + rewritten fill
    pins + §12 restricted/non-restricted contract (220 checks);
    `tests/forever_secret_compat_state.lua` gained §7 raw-reader contract (170 checks).
- **Current state (verified 2026-11-06):**
  - red-first captured: new power_bar suite failed on the old tree (no raw read, nil-pair
    fallback, no StatusBar, track reads absent); compat suite failed on the missing
    `api.GetPlayerPower`.
  - green: `power_bar_state.lua` 220 checks PASS; `forever_secret_compat_state.lua` 170/0;
    `luacheck` 0/0 on the five touched files, whole-tree floor unchanged 2 warnings / 0
    errors in 100 files; LF kept; no lint-config change.
  - mutations: `desks/powerbar-fix/run_mutations.sh` → `6/6 killed` (nil-the-secret-again,
    arithmetic-on-secret, compare-on-secret, hide-instead-of-show, format-the-secret,
    weakened nil-on-secret contract), isolated `/tmp` copies, pristine baseline first.
  - diag restricted path proven by an ad-hoc opaque-sentinel script (6/6) because
    `tests/diag_state.lua` is outside this desk's write scope — FILED, not edited.
  - full harness snapshot 2026-11-06 14:31:40: `57 steps, 4 failed` — all four reds are
    the concurrent display/perf lanes (`hunter_state`, `main_init_state` A-2,
    `engine_matrix_state` forever payload, `wiring_check` stale `main.lua` accept
    entries); the desk's own harness steps (diag_state, secret_guard_state,
    forever_secret_compat_state, power_bar_state, toc_check) all pass, and an A/B copy
    with the additive compat block removed reproduces the same `main_init_state`/
    `engine_matrix_state` reds.
- **Artifacts:** `bench/powerbar_secret_2026-11-06.md` (root cause, fix, evidence,
  mutation table, crossfire attribution, UNVERIFIED list, follow-ups);
  `desks/powerbar-fix/run_mutations.sh`.
- **UNVERIFIED (needs the client):** the real secret surface (opaque on arithmetic), the
  tainted-addon StatusBar acceptance, `Interface\\Buttons\\WHITE8X8` asset presence on
  Forever (fallback documented), font-string layering, and the perceived appearance.
- **Next step:** operator in-client check on Forever — the bar should stay visible with a
  `?` label during a restricted read, and `/st diag` verbose should show
  `value=restricted fraction=? why=-`. If it is still missing, `why=` names the gate.
  Follow-ups filed: `tests/diag_state.lua` restricted pin (owner of that file) and the
  display/perf crossfire reconciliation (Lead).

## 2026-11-06 — [signal:done] powerbar-fix done

- `compat.lua` (`api.GetPlayerPower` raw reader) + `power_bar.lua` (real StatusBar fill,
  restricted raw pass-through, `?` label) + `diag.lua` power line; two suites extended
  (220 + 170 checks); 6/6 mutation kills; in-client check owed.
