# options-pass — Journal

## 2026-10-19 — Desk opened
- **Purpose:** the options pass — build the missing option widgets + their documented
  defaults (spec **BS-7** of `bench/filed_closure_sweep_2026-10-19.md` §7) plus the
  filed **HU-9** badge-toggle widget (the practice level badge had no widget, so with
  its default ON the user could not turn it off in-game).
- **Scope:** `option_tables.lua`, `config_presets.lua`, `tests/options_load_state.lua`,
  and `tests/shaman_guide_state.lua` (**only** the Flame-Shock-refresh pins). OUT:
  `practice*.lua`, `classes/*.lua`, `guide_contract.lua`, `hud_state.lua`, `main.lua`,
  `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, TOCs, versions, README,
  CHANGELOG, docs. No git. No lint-config changes.
- **Rules carried:** every widget needs its verified live consumer (cited); nil-safe
  reads (nil = off); no default-visible change beyond the operator-gated badge
  default; preserve line endings; touched-lines whitespace only; mutation proofs on
  `/tmp/opencode` copies.
- **Next step:** read the sweep §7 + the live consumers, build the four surfaces
  (Forever Rend toggle, TBC mana-sustain threshold default, Flame-Shock refresh
  default 3 → 0, practice level-badge toggle), pin them in `tests/options_load_state.lua`
  (+ the FS pins in `tests/shaman_guide_state.lua`), run the full harness + luacheck
  and the mutation proofs, then file the bench artifact and the signals.

## 2026-10-19 — [signal:done] BS-7 options pass + HU-9 badge toggle landed
- **Worked on:** the four BS-7/HU-9 surfaces, options-only. (1) **Forever Rend upkeep
  toggle** (W-15) — new widget `option_tables.lua:3817-3844` (warrior panel, order
  4.132), key `guide_forever_rend_upkeep`, **no default ships** (nil = off; documented
  at `config_presets.lua:1255-1269`). Consumer: the engine half is live
  (`warrior_guide.lua` `should_maintain_rend_outside_arms`, `REND_REFRESH_DEFAULT = 3`,
  rule R at `:1154-1160`); the provider half is the **filed** line
  `classes/warrior.lua:3049-3053` (the warrior lane's file) — until it lands the key
  is armed but the rule stays dormant. (2) **TBC mana-sustain threshold** (P-22) — the
  0-100 range widget already existed (`option_tables.lua:2218-2243`); the **default**
  is new: `twist_mana_threshold_pct = 0` (off) at `config_presets.lua:682-697`, with
  the reason and the citation. Live consumer: `classes/paladin.lua:3281-3285` ->
  `nextaction.lua:556-557`. (3) **Flame Shock refresh 3 -> 0** (BS-4c) —
  `config_presets.lua:1062-1077`, comment block rewritten (the sim re-applies only
  when the dot is INACTIVE, so 0 is the sim-exact expiry-only value). (4) **Practice
  level-badge toggle** (HU-9) — new widget on the Progress page
  (`option_tables.lua:806-846`, order 5.1) driving the module's own entry points
  `st.practice_ui.badge_is_enabled` / `set_badge_enabled` (`practice_ui.lua:1116-1142`).
  Nil-safe both ways (no module -> getter false, setter no-op).
- **Current state:** `tests/options_load_state.lua` **3408 checks / 0 failed** (new
  §24(e) badge-widget block + new §25 Rend block; the SIM and MANA pins re-cut).
  `tests/shaman_guide_state.lua` FS pins green (the rule-6 boundary pins re-cut to
  "refresh on expiry" + fresh coverage of the engine's own 3 s fallback; the frame
  block re-cut to expired-vs-live + an explicit-override case). Full harness
  `bash tests/run.sh` -> **41 steps, 0 failed**; `luacheck .` -> **2 warnings / 0 errors
  in 83 files** (the tree floor; the four files this lane touched are 0/0). Line
  endings preserved (all four files LF); no trailing whitespace introduced.
  **Mutation proofs 11/11 killed** on `/tmp/opencode/bs7_mut` (full tree copy; each
  mutation applied -> checked -> restored byte-identically): scripts
  `/tmp/opencode/bs7_mutations.py`, `/tmp/opencode/bs7_mutations2.py`.
  Bench artifact: `bench/buildout_options_pass_2026-10-19.md`.
- **Filed for others (named, not guessed):** the Forever Rend **provider read**
  (classes/warrior.lua — one line; the exact shape is in the bench artifact §4.1); a
  **non-zero mana-sustain threshold is operator-gated** (no cited percentage —
  `docs/research/tbc_minmax.md:27` names none — so it ships off; bench §4.2);
  `classes/shaman.lua:3264`'s `or 3` gather fallback still says 3 (shaman lane);
  the Flame Shock slot's cooldown swipe no longer rides at threshold 0 (design call
  for the shaman lane — bench §4.4); two stale comments in class files (read-only for
  this lane — bench §4.5). HU-9's row: the widget landed; the operator closes it.
- **Crossfire note (not a defect of this lane):** the shaman lane (BS-4) was editing
  `classes/shaman.lua`, `shaman_guide.lua`, `tests/shaman_state.lua` and the shaman
  sections of `tests/shaman_guide_state.lua` LIVE during this lane's run (23:17-23:33).
  Its in-flight state briefly broke `classes/shaman.lua`'s 200-local budget (the
  sibling fixed it) and it edited `tests/shaman_guide_state.lua` — a file this lane
  also owns for the FS pins. Both sets of pins are in the file and both are green;
  the reconcile owner should confirm the two edits did not interleave badly.
- **Next step:** the orchestrator validates (this lane's claims are offline only — no
  in-client observation). The two open operator items are the Forever Rend provider
  read (warrior lane) and the P-22 threshold value (operator order).
