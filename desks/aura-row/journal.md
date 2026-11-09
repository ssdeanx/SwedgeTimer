# Desk: aura-row

## 2026-11-08 — Forever-only per-class aura icon row implementation (task t4, attempt cf530ca1)

- **Worked on:** read `bench/briefs/brief_aura_row_impl_2026-11-08.md` and the t2 port map
  (`bench/aura_row_reference_2026-11-08.md`, 869 lines) end to end before touching a file; re-read
  `AGENTS.md` (Cross-engine / Gotchas / Workshop mechanics), `desks/journal.md` tail, the `hud.lua`
  header + lockdown pattern, `bars.lua:939-966` hand/frame helpers, `main.lua` `init_libs`/`post_init`/
  `init_weave_range`, `config_presets.lua` `ST.class_defaults`, the `option_tables.lua` HUD section and
  its hidden-gate pattern, `SwedgeTimer.toc`, `tests/run.sh`, `tests/toc_check.lua`. Verified the
  Forever API surface again against `/home/sam/wow-ui-source` `origin/forever` (tip `eac30af5`,
  `1.60.1.70790`): `Blizzard_AuraContainer` load flags (`## AllowLoad: game`, not LoadOnDemand) and the
  `_G.AuraContainerSortMethod/Direction = securecopy(...)` re-exports (so the load-time gate is sound);
  `AddAuraGroup` validation + `securecopy` of `includeSpellIDs` + `AddForbiddenAspects`; flow-layout
  `secretwrap` sizing; the aura-button setter nilability (`SetDurationText`/`SetDurationBar`/
  `SetApplicationCount` options are Nilable); `Blizzard_CustomAuraContainer.xml` `allowUntaintedCreation`.
- **Built:** NEW `aura_icons.lua` (1279 lines) — Forever-only gate (`st.family == "FOREVER"` + the
  three native globals), six per-class post-merge Forever buff/debuff id tables (97 / 160 ids, shared 5,
  racial 10 keys, 27019 + removed-druid ids excluded, stance tier never merged), native `AuraContainer`
  rows (`HELPFUL`/player, `HARMFUL|PLAYER`/target) with `includeSpellIDs` merged at creation only,
  button styling (icon/border/client-owned duration text/stacks/optional debuff duration bar), a
  plain-Frame driver with a 0.15 s maintenance pass + 0.5 s no-latch creation retry + forced
  `PLAYER_ENTERING_WORLD` pass, topmost-VISIBLE-bar selection from plain swing-bar geometry only, a
  FIXED reserved band (never measure an aura container — its geometry can be secret), combat deferral
  of the native containers, options resolution (nil = shipped default), and a nil-safe diagnostics
  read model. Wired: `SwedgeTimer.toc` (after `hud.lua`), `main.lua` guarded seam
  `ST:init_aura_icons()` + one `post_init` call, `config_presets.lua` five shipped defaults,
  `option_tables.lua` `ST:aura_icon_options_args()` (hidden on every non-Forever family) merged into
  the Behaviour page, `tests/run.sh` registry, `tests/toc_check.lua` `REQUIRED_MODULES`.
- **Tests:** NEW `tests/aura_icons_state.lua` (1582 lines, 14 sections, 853 checks) written RED FIRST
  (suite exited 1 on the missing module) and then driven green against the real module in an
  instrumented frame sandbox whose aura globals are booby-trapped (`UnitAura`/`C_UnitAuras` raise and
  count). `lua5.1 tests/aura_icons_state.lua` → 853 checks / 0 failures. Full `bash tests/run.sh` →
  59 steps / 0 failed, luacheck 9 warnings / 0 errors in 105 files (the two new files are 0 warnings);
  `luac5.1 -p` clean.
- **Mutation proofs:** 12 anchored single-line reversions on isolated `/tmp` copies (rsync excludes
  `.git`/`Media`/`Images`/`docs`/binaries/team state), each exit 1 with a recorded failure count:
  gate-family 55, own-caster filter 2, top comparator 15, container-measure 9, shared merge 11,
  creation latch 4, 27019 4, throttle 2, secret-geometry guard 3, option family 5, main seam 2, TOC
  line 3. The M9 run exposed a real test weakness (the fake secret was a table, so the type guard
  alone rejected it); the suite now uses a numeric secret sentinel so only `st.api.is_secret` can
  reject a secret number. All 12 now fail correctly.
- **Current state:** implementation complete, all gates green, `bench/aura_row_2026-11-08.md` on the
  bench with the file:line map, gate/lifecycle diagram, shipped id tables + provenance, test evidence,
  the 12-row mutation table, and a 15-row UNCONFIRMED in-client checklist with exact `/run` probes.
  Nothing in this lane needs operator input to sit for review; the in-client items (U1-U15) need a
  Forever session, which no offline lane can substitute.
- **Next step:** the Lead's review lanes can check the two files + four wiring hunks; the operator
  closes U1-U15 in a Forever session — most importantly U1 (tainted template creation), U7 (secret-safe
  in combat), U8 (container SetPoint in combat), U9 (container geometry secrecy) and U10 (topmost-bar
  visual stack per class).
