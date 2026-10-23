# Final full-tree nil sweep — 2026-10-22

Desk `nil-sweep-tree` (last lane of the release wave). Scope: every shipped root module
EXCEPT `classes/*.lua` (completed by `swing-nil-sweep`: 41 fixes, 50 legs), plus legs in
the owning suites. Off-limits and untouched: `classes/`, `tests/run.sh`, `Libs/`, TOCs,
versions, `bench/`, `desks/` (except this desk's trail).

## Skills confirmation

All four lane skills were present at this seat and run as written:
`bench-read` (journals first: `desks/journal.md`, `desks/swing-nil-sweep/journal.md`,
`bench/swing_display_2026-10-22.md`, `hands-up.md` HU-15/HU-22/HU-29), `desk-open`
(`desks/nil-sweep-tree/` created with journal), `desk-journal` (trail below + desk
journal), `signal-write` (done signal in `desks/nil-sweep-tree/.signals/`). No skill was
missing; no manual equivalent was needed.

## Method

1. Enumerated shipped files from `SwedgeTimer.toc` (all flavor variants carry the same
   root set) — 38 root modules.
2. For each: located every per-frame entry (OnUpdate drivers, 0.05 s/0.2 s C_Timer polls,
   per-tick class hooks) and per-event entry (AceEvent handlers, lib callbacks, frame
   OnEvent, user-driven cast/drag/options events).
3. Classified each index chain on those paths: GUARDED (nil is a documented runtime
   state and handled), CONTRACT (single writer/owner proves non-nil; no dead armor
   added), or UNGUARDED (nil state reachable → fixed).
4. Fixes use the file's own idiom; each states what it preserves and why absence is
   legitimate. Legs added to the owning suite; each fix reverted in a `/tmp/opencode`
   copy to prove the leg fails red-first.

Legitimate-nil states used in classification: lazy-unbuilt hand (HU-22), no class row
(unsupported class / pre-AceDB caller / sandbox), empty inactive class module (operator
selected-class rule), optional module/frame/lib, unknown class token. `option_tables.lua`
and `designmode.lua` class-row reads are CONTRACT: AceDB's `profile["**"]` metatable
creates the class table on first access (`Libs/AceDB-3.0/AceDB-3.0.lua:96-130`), and
`self.db` exists before `set_opts()` (`main.lua:419-426`).

## Fixes (31 guard sites in 8 modules; table rows 8 and 13 each cover multiple call sites)

### main.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 1 | `get_class_table` :233 | `return self.db.profile[self.player_class]` (throws pre-db/missing profile) | returns nil when `self.db`/profile absent | every caller already branches on nil (`bars` pcall+type, `hud` pcall, `practice` type) |
| 2 | `get_hand_table` :247 | `...profile[class][hand]` | nil when class row absent | same seam; unconfigured hand reads "not configured / not built" |
| 3 | `check_bar_enable_settings` :282 | `db_class.class_enabled` first | nil class row → `false` | bar cannot be enabled without settings; practice exemption still returns true first |
| 4 | `activate_class` :750 | `get_class_table().class_activation` | nil row → selection nil → Auto | shipped default is Auto (activate the playing class) |
| 5 | `post_init` :958/:996 | `db_class.timers_locked` | nil row → locked | shipped `class_defaults.timers_locked = true` |
| 6 | `COMBAT_LOG_EVENT_UNFILTERED` :1059 | direct `self.PALADIN/WARRIOR.on_combat_log_unfiltered` call | module+hook presence guard | only the selected class module is populated; neutral pre-pass still runs every event |
| 7 | `UNIT_POWER_FREQUENT` :1825 | `self[self.player_class].on_rage_update` | module+hook presence guard | rage hook runs when the module is active; no throw when it is not |
| 8 | `UNIT_SPELLCAST_FAILED_QUIET` :1959 / `SUCCEEDED` :1971 | direct class-table index | module+hook presence guard | same dispatch shape as the other class hooks |
| 9 | `determine_form_visibility_flag` :2222 | `db.form_vis_*` | nil row → flag false | no form preferences ⇒ hidden (fail-closed, never a guessed form) |
| 10 | `bar_is_enabled` :2535 | `db.enabled` | nil hand row → `false` | same state as a disabled hand |
| 11 | `handle_bar_visibility` :2556 | `db.show_behaviour` | nil hand row → `hide_bar` | a bar may only be visible because its configuration says so |
| 12 | `set_bar_visibilities` :2623 | `db_class.class_enabled` | nil row ⇒ disabled branch | 0.05 s poll never throws; hides every hand exactly like `class_enabled=false` |
| 13 | `class_on_aura_change` :2795 / `class_on_current_spell_cast_changed` :2802 / `class_on_spellcast_event` :2809 | `self[c].hook` | module+hook presence guard | event dispatch with no class token is a no-op |
| 14 | `post_init` class-hook lookup :973 | `self[self.player_class].post_init` | module+hook presence guard | shared widget pass still runs; class hook only when the module exists |

### practice_ui.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 15 | `ui.cast_key` AW block :5825 | `db.practice_aw_includes_pot` | nil row → `{}` read (module's own idiom, same as `apply_settings`/`show_result`) | shipped AW defaults: both pieces off; never a throw out of the cast handler |
| 16 | `ui.save_position` :6445 | writes `db.practice_panel_x/y` | nil row → return | the drag still moved the live panel; nothing claims a save that has nowhere to land (same rule as `maybe_save_bests`) |

### weave_range.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 17 | `st.weave_range.update` :196/:203 | `class_db.weave_range_enabled` | nil row → hide + return | 0.2 s poll; no row ⇒ no toggle ⇒ the off state |

### designmode.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 18 | `DM.enter` :1125/:1140 | `unlock_elements` → `lock.get()` → `get_class_table().timers_locked` threw | no class row → one visible refusal, session stays off | design mode's job is persisting per-class positions; with no row every save path would fail, so refuse loudly (never a silent session) |
| 19 | `bar_descriptor.reset` :727 | `hand_db.x = ...` | nil hand row → return | no stored position to reset |

### hunter_ui.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 20 | `ui.build` :370 | `db_hand.bar_texture_key` | nil ranged row → `false` | `ui.init` retries on the next tick; no half-built UI |
| 21 | `ui.update` :1547 | passes nil `db` into every sub-site (guard-quarantine storm) | nil row → `hide_all` + return | hidden is the same state a switched-off UI paints; no error volume |
| 22 | `ui.sync_melee_anchor` :506 | `get_class_table().timers_locked` | nil row reads as locked (no re-anchor) | shipped default `timers_locked = true` |

### hud.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 23 | `HUD.init` :658 | create → `apply_settings` nil read | nil row → return (not inert) | per-tick class hook retries; the row may appear with a profile switch |
| 24 | `HUD.on_bar_update` :691 | `layout_changed` nil read | nil row → return | creation/layout only when settings exist |
| 25 | `HUD.on_update` :1346 | `layout_changed` nil read each tick | nil row → hide + return | driver never throws; hidden row |

### rotationtext.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 26 | `RT.on_update` :484 | `layout_changed` nil read | nil row → hide + return | driver tick safe; label hidden |

### nextaction_ui.lua

| # | site | before | after | preserves |
|---|---|---|---|---|
| 27 | `ui.should_show` :449 | `db.nextaction_enabled` | nil row → `false` | hidden guide |
| 28 | `ui.apply_settings` :847 | `db.nextaction_enabled` | nil row → hide + return | frame stays built; hidden state |

## Per-file verdicts (all 38 shipped root modules)

| module | per-frame / per-event entries | verdict |
|---|---|---|
| main.lua | 40 AceEvent handlers, 6 lib callbacks, 0.05 s range poll, 0.05 s aura poll, C_Timer callbacks | 14 rows / 17 sites fixed (#1-14); rest guarded: swing handlers `self[hand]` guard (:1370,:1450,:1490), GCD/LATENCY handlers write `self.gcd/latency` created in OnInitialize (:617,:628), `SWING_TIMER_STOP` db read guarded (:1470), equipment/combat/aura handlers init-guarded (:1540,:1700,:1780), talent handlers nil-safe (`select(5,...)`) |
| bars.lua | `onupdate_common` :679 + 3 hand OnUpdates :841-849; 9 `configure_*`; 0.2 s feeders; `on_bar_active/inactive` | GUARDED: built/frame/state/db/cycle-type guards (:680-708); every setter `bar_is_built`-guarded; widget children created once in `init_visuals_template` (:120-155, single constructor ⇒ CONTRACT) |
| hud.lua | driver OnUpdate :649 → `on_update` :1346; class hook :691; CLEU OnEvent :604 | 3 entry guards added (#23-25); internals guard frames/icons; class-row reads CONTRACT for a created HUD (creation only after a provider class) |
| practice_ui.lua | driver :2228 → `ui.tick` :5364; cast/drag/button/options events | tick guarded (`ui.active`, `st.practice`, quarantine, pcall compute); 2 reads fixed (#15-16); helpers (`update_*`, `sync_to_addon`, `refresh_icons`) all frame/sim nil-guarded |
| practice.lua | `st.practice.tick` :838 (per-frame, caller-pcall'd) | GUARDED BY CALLER CONTRACT: sim tables created by `new sim` (:235-243); tick runs inside `pcall` + quarantine (:5430-5450 practice_ui); `apply_haste` args type-guarded (:345) |
| practice_stats.lua | `record_attempt` :275, `record_session` :337 (session events) | GUARDED: state/summary type guards + `num`/`count` normalizers |
| practice_progress.lua | `record_attempt` :637, `end_session` :716 (session events) | GUARDED: progress/session/opts type guards, `class_scope` nil-return |
| practice_progress_ui.lua | `refresh_frame` :1113, `build_frame` :876 (panel/session events) | GUARDED: `ui.frame` guard, model/`num`/`count` guards; UI built lazily |
| compat.lua | per-tick wrappers (`get_time` :1460-1476, `UnitDistance` :1023, `UnitAttackSpeed`, `UnitRangedDamage`, `GetSpellInfo`) | GUARDED: pcall/probe/secret/NaN guards per wrapper (the pattern the class sweep builds on) |
| swing_source.lua | engine OnEvent :424 (PLAYER_SWING etc.) | GUARDED: hand/type/duration rejected with counters; cycles table contract; speed reads pcall'd (:250-300) |
| enemy_swing.lua | driver OnEvent :660; OnUpdate :409 | GUARDED: frame/clock/cycle checks in `on_update` (:452-470); feature/target guards in every handler (:506-640) |
| LibGlobalCooldown.lua | OnEvent :245 dynamic `lib[event]` dispatch | GUARDED BY REGISTRATION SET: the six registered events all have handlers (:150,:165,:199,:203,:207,:216); no per-tick path |
| LibLatencyMonitor.lua | OnEvent :84 | GUARDED: one-shot registration guard |
| utils.lua | `print_msg` (every message), `fetch_font_path`/`apply_font` (frame builds) | CONTRACT for `DEFAULT_CHAT_FRAME` (always present in-client; sandbox stub); font chain fully pcall-guarded |
| guard.lua | `run`/`note`/`refusal` (every guarded site, incl. per tick) | GUARDED: owner/site/type guards throughout |
| widgets.lua | options-time dropdowns/sound preview | GUARDED: lazy addon, pcall upvalue probe, sound map nil-guarded |
| design.lua | pure snap/grid maths (per drag frame) | GUARDED BY CALLER: `drag_tick` guards cursor/target before calling |
| twist.lua / weave.lua | pure engines called per tick from class modules | GUARDED: numeric args/type guards; input tables built by the class modules (class sweep) |
| nextaction.lua / warrior_guide.lua / druid_guide.lua / shaman_guide.lua / hunter_guide.lua / rogue_guide.lua | `evaluate` per tick | GUARDED: `inputs = inputs or {}` + per-field defaults/type guards |
| hunter_window.lua | pure helpers per tick | GUARDED: every entry type-checks its numeric args |
| druid_energy.lua | pure helpers per tick | GUARDED: type/NaN guards on every entry |
| designmode.lua | layer OnUpdate :344, `drag_tick` :557, options/control events | per-frame guarded (`layer` check, `DM.refresh` frame pcalls, drag target/cursor guards); 2 event sites fixed (#18-19) |
| hunter_ui.lua | `ui.update` :1547 (per tick), `sync_melee_anchor` :506, `build` :370, drag | 3 sites fixed (#20-22); sub-updaters individually `st.guard.run`-isolated |
| rotationtext.lua | driver :553 → `on_update` :484 | 1 site fixed (#26); creation provider-gated; remaining events CONTRACT (provider class row) |
| nextaction_ui.lua | frame OnUpdate :433 + class hook → `update` :754 | 2 sites fixed (#27-28); provider gate + guard contract |
| ldb.lua | `update` :195 (per frame, mainhand) | GUARDED: obj lazy-init, `self.mainhand` type check, throttle, `--` sentinel |
| diag.lua | `wrap_onupdate` :278 (per-tick wrapper), error handler | GUARDED: type check on `original`, `read()` pcall chain, no throw |
| option_tables.lua | AceConfig getters/setters/hidden/disabled (panel refresh) | CONTRACT: class row auto-created by AceDB `**`; db exists before `set_opts`; no per-frame path |
| option_table_presets.lua | option construction at `set_opts` | CONTRACT: build-time only, `UnitClass` result nil-safe (`or "Unknown"` in labels) |
| config.lua | static defaults table | GUARDED BY LOAD ORDER: all 10 referenced `ST.<CLASS>.defaults` defined in `config_presets.lua`; `config_presets` precedes `config` in every TOC |
| config_presets.lua | static defaults | no runtime chains |
| weave_range.lua | driver :184 → `update` :196 | 1 site fixed (#17); range/target gates hide on unknown |
| swing_source / enemy_swing / Lib* | covered above | — |

## Validation

Focused suites (owner: orchestrator for the full `run.sh`):

```
main_init_state      PASS  (1047 checks)
practice_ui_state    PASS  (2542 checks)
weave_range_state    151 checks, 0 failures
designmode_state     670 checks, 0 failed
hud_state            PASS  (844 checks)
rotationtext_state   PASS  (246 checks)
hunter_state         PASS  (1794 checks)
guide_contract       PASS  (1057 checks)
bars_state           PASS  (935 checks)   [regression, unchanged]
options_load_state   3501 checks, 0 failed [regression, unchanged]
practice_state       PASS  (1533 checks)  [regression, unchanged]
```

`luacheck` on the 8 touched source files: 0 warnings / 0 errors. Repo-wide floor
unchanged: **2 warnings / 0 errors in 90 files** (main.lua's pre-existing `table.pack`
warning + one pre-existing other). Line endings preserved per file (CRLF: main,
practice_ui, designmode, hud, rotationtext, nextaction_ui; LF: weave_range, hunter_ui) —
verified by byte count, zero bare-LF lines in CRLF files.

## Mutations (fresh /tmp/opencode copy per mutation, removed after)

27/27 killed — each reverted exactly one fix, and the owning suite failed on the matching
NILSWEEP leg with the unguarded error quoted:

- M1 accessors → N1 `attempt to index ... profile`; M2 enable check → N5; M3 form flag →
  N6/N7; M4 bar enabled → N3; M5 visibility → N4; M6 set visibilities → N2; M7 post-init
  lock → N7/N12; M8 activate → N7 (init aborted); M9 CLEU → N9 `attempt to call field
  'on_combat_log_unfiltered' (a nil value)`; M10 rage → N10; M11a helpers → N11 (3);
  M11b spellcast handlers → N11 (2); M11c post-init hook → N12; M12 AW → P1; M13 save
  position → P2; M14 weave update → W1 (both checks); M15 design enter → D1 (4);
  M16 design reset → D2; M17 hunter build → HU1; M18 hunter update → HU2 error-volume;
  M19 hunter sync → HU2; M20/21/22 HUD init/on_update/on_bar_update → H1/H2/H3;
  M23 rotation on_update → R1; M24/25 guide should_show/apply → G1/G2.
- Two legs were strengthened after the first run exposed short-circuits (N10 needed the
  nil class token, not an empty module; HU2 needed the cast bar visible so the lock read
  is evaluated) — same correction pattern as the class sweep's 5 strengthened legs.
- Copies removed; fixed-tree suites re-ran green after.

## UNVERIFIED (evidence that would close each)

- U1 in-client behavior of every fail-safe state: no class row (unsupported class),
  inactive class module (explicit `class_activation` pick of another class), design-mode
  refusal. Needs the operator's copy session; close with: log clean while playing an
  unsupported class / after switching `Class module`, and the design-mode refusal line
  appearing instead of a Lua error.
- U2 the reported `practice_ui.update_result_font` guard `type(result.text) ~= "table"`
  (pre-existing, not touched): if a client's FontString is userdata rather than a table,
  the guard returns early and the result font is never applied. Not a nil-sweep chain;
  filed as an observation for the options/UI lane, UNCONFIRMED in-client.
- U3 `option_tables.lua:81` lowercases `ST.player_class` at file load; `OnInitialize`
  overwrites it with the uppercase token. No runtime path observed that reads the
  lowercase value in between, but the ordering is load-order sensitive and worth a pin
  in a future options lane (out of this sweep's write scope).
