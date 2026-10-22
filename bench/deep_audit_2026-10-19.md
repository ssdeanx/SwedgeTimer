# Deep enterprise audit — 2026-10-19 (hunter, read-only)

Session `ses_ea98586ecffepElQEB3S89Vj3M`. Filed by the orchestrator (hunter has no write
tools). 33 addon `.lua` + 7 TOCs + vendored-lib semantics. ~95 error-handling/fallback
locations reviewed; 72 `pcall` sites, 6 `run_guarded` sites, 4 retry/cap mechanisms.

**VERDICT: FINDINGS 14** — 2 material (F1, F2), 4 medium (F3–F6), 8 low/smell (F7–F14),
10 justified exceptions.

Mid-edit at audit time (owned by the gamification-foundation lane, not defect-audited):
`practice_progress.lua`, `practice_stats.lua`, `config_presets.lua`, `tests/run.sh`, the 7 TOCs.

---

## Ranked findings

| # | Sev | Location | Defect | Required fix |
|---|-----|----------|--------|--------------|
| F1 | HIGH | `diag.lua:524` `install_error_handler`; `:592` `error_lines` | **The error-handler chain is never installed** — no caller in the whole tree. The ring is never written, so `/st diag` prints "errors none" as a *fact* when nothing could have been observed. A diagnostic that lies is worse than no diagnostic. | (1) call `st.diag.install_error_handler()` once at init (`main.lua` `init_libs`, after `interfaces_are_initialised`); (2) `error_lines()` must distinguish "handler installed, nothing thrown" from "handler NOT installed"; (3) uninstall on `PLAYER_LOGOUT`. |
| F2 | HIGH | `main.lua:408` `has_oh = false`; `:1112` guard; `:545-551` registration | `PLAYER_TARGET_SET_ATTACKING` is registered on every classic-line client but `self.has_oh` is **never set true** → the handler body always returns at the guard. The offhand recolour is a silent no-op in production; the suite sets the flag by hand (tests `main_init_state.lua:793/829/910`), so the harness cannot see it. | Drive `has_oh` from the real offhand-presence signal (`check_weapons()` already derives `offhand.has_weapon` from `api.UnitAttackSpeed("player")`, `main.lua:682-689`); nil-guard both operands (`offhand.start`/`offhand.speed` are nil before the first swing / on the inert stand-in). If the feature is unwanted, delete handler + registration + field rather than leaving a registered dead event. |
| F3 | MED | `diag.lua:104-112` `print_line` → `pcall(print, text)` | The report's only output path is the bare global `print`; if absent/shadowed the pcall fails and **the whole report vanishes silently**. Every other output in the addon uses `st.utils.print_msg`. | Fall back to `st.utils.print_msg` / `DEFAULT_CHAT_FRAME:AddMessage` when `print` is not a function; announce the fallback once. |
| F4 | MED | `compat.lua:1268-1282` `get_family_spell_id` | It probes with **numeric ids**; TBC Anniversary resolves by **name** (operator-confirmed, `bench/lessons.md:29-32`) → every lookup returns nil on TBC, indistinguishable from "rank absent", and callers **latch false** (`classes/druid.lua:94`, `classes/warrior.lua:369`) so a cold TBC book never re-resolves. | Route the id walk through `api.get_spell_query(name, id)` per family, or add an explicit family branch; make "not resolvable" distinguishable from "resolved false" so the latch is not poisoned. |
| F5 | MED | `hud.lua:660-670` `HUD.cleu_register_errors` | Write-only counter — the comment names a `/st diag` reader that **does not exist**. The failure itself is announced once, but the volume is invisible. | Add the counter to the `/st diag` runtime line, or delete the counter and the claim. |
| F6 | MED | `SwedgeTimer.toc:1` Interface list + `:18` `LibClassicSwingTimerAPI` | The base TOC advertises Retail/Forever interfaces **and** ships the classic-combat-log lib, whose file-scope `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` (`LibClassicSwingTimerAPI.lua:786`) **throws** on those clients → the whole addon fails to load if a flavor TOC is not selected (e.g. name-casing on a case-sensitive loader). | Either drop the mainline interfaces from the base TOC, or don't ship the classic lib from it, or assert the invariant in `tests/toc_check.lua`. **Operator-level decision** (the base TOC advertising the matrix is a prior decision). |
| F7 | LOW | `main.lua:1706-1713` `ST:needs_gcd()` | No callers. Reads `get_hand_table("offhand"/"ranged")` for every class; through AceDB's `**` metatable those **auto-create as synthetic tables** — a future caller gets a plausible non-real table. | Delete it, or wire it and document what it gates. |
| F8 | LOW | `classes/hunter.lua:511` vs the other five | Per-frame class-hook order diverges: hunter runs HUD **before** guide; the other five run guide first (warrior 2396→2404, paladin 1689→1696, rogue 1688→1694, shaman 2428→2436, druid 1362→1371). | Pick one order, apply in all six. |
| F9 | LOW | `classes/paladin.lua:309/328/336` | `post_init` UI init order differs for paladin (guide→practice→HUD) vs the other five (guide→HUD→practice). | Pick one order, apply in all six. |
| F10 | LOW | `bars.lua:517-541`, `hud.lua:210-260`, `nextaction_ui.lua:728-775`, `practice_ui.lua:572-592` **and** `:3966-3998`, `rotationtext.lua:243-283` | The `run_guarded` isolation contract is implemented **six times** with six quarantine constants — and already diverged (`note_start_block` prints on every refusal, the other five print once). | One shared `st.guard.run(owner, site, fn, ...)` helper (new root module, all 7 TOCs) with per-site message text as a parameter. |
| F11 | LOW | `main.lua:1023/1032/1036/1122/1130/1144/1155` | `assert(event == event)` used as a luacheck "unused argument" silencer in seven production handlers — a runtime assert doing a linter's job, and a tautology a reader must decode. | Named `_event` parameter + documented luacheck config (the wire-not-strip rule bans `_` in the *body*, not in a parameter name). |
| F12 | LOW | `bars.lua:1185` | Raw global `print` in a live error path (not pcall-wrapped) — inconsistent with the addon's chat-output policy and would throw on a client without `print`. | Use `st.utils.print_msg`. |
| F13 | LOW | `classes/hunter.lua:715-717`, `classes/warrior.lua:1232-1234`, `diag.lua:518-520`, `practice.lua:1411` | `table.remove(list, 1)` inside a trim loop → O(n²) memmove per event on the combat path (caps are small, so bounded today). | Ring buffer or index offset. |
| F14 | LOW | `practice_stats.lua`, `practice_progress.lua` | Neither module is on any TOC → they load on **no** client, so the progress/persistence feature is invisible while the code "exists" — a silent no-op of exactly the kind this audit targets. | Add both to all 7 TOCs in order (`practice_stats.lua` → `practice_progress.lua`). |

---

## Per-feature call-path trace (every hop)

| Feature | Path | Isolation | Gap/cycle |
|---|---|---|---|
| Bars | engine select `main.lua:34-44` → callbacks `main.lua:667-674` → `ST.callback_event_handler` `main.lua:798-829` → `SWING_TIMER_*` `main.lua:901-1017` → `set_bar_color` `bars.lua:1019` → OnUpdate `main.lua:663` → `bars.lua:698-708` → `onupdate_common` `bars.lua:573` → fill/text `bars.lua:602-612` → class hook `run_guarded` `bars.lua:681` → zones `bars.lua:686-688` → `st.ldb.update` `bars.lua:694`. Visibility: `rf_update` `main.lua:1495` → `set_bar_visibilities` `main.lua:1683` → `handle_bar_visibility` `main.lua:1623` → show/hide `main.lua:242/204`. | `bars.lua:579-591` (engine-dead label), `:592-600` (no-cycle neutral), `:517-541` (quarantine 25), `main.lua:815-828` (callback isolation), `main.lua:1495-1573` (bounded retry + terminal disable) | none / none |
| HUD | class `post_init` → `st.hud.init` (6 classes) → `ensure_created` → `create` → `build_driver` `hud.lua:676-685` → `HUD.on_update` → `update_display` `hud.lua:1196` → per-icon `pcall(call_hud_provider,…)` `hud.lua:1224` → class provider. Pickup: class hook → `st.hud.on_bar_update` | `hud.lua:1221` quarantine, `:1224-1231` per-slot hide, `:656-670` CLEU pcall, `:807-811` lockdown defer | none / none |
| Guide | `post_init` → `resolve_guide_icons` → `st.nextaction_ui.init` → frame build → class hook → `nextaction_ui.on_bar_update` `nextaction_ui.lua:866-873` → `ui.update` (throttle) → `pcall(provider.gather)` `:822` → `pcall(provider.evaluate)` `:844` → `display_active/idle` `:856/:862` → pure engine | `:818-830`, `:828-830`, `:841-852`, `:880-904` | none / none |
| Practice | `/st practice` `main.lua:1771-1776` → `practice_ui.toggle` → `ui.start` `practice_ui.lua:3389` → refusals → `note_start_block` `:577-592` → drill session → `ui.tick` `:4009` → per-class tick `:4078-4096` → `pcall(pr.tick…)` `:4102` → `pcall(pr.determine_rotation…)` `:4165` → cast handlers → `show_result` → `update_result_fade` `:2777`. Bar ownership `main.lua:208/220`. | `:3966-3998` tick isolation, `:4000-4007` quarantine, `:589-591` refusal print | none / **gap**: persistence modules on no TOC (F14) |
| Designer | `/st design` `main.lua:1777-1784` → `designmode.toggle` → registry `dm.registry:register` (from `ST:new_pips` `bars.lua:1183`) → elements HUD/rottext/guide/practice-panel `designmode.lua:697-802` → grid `:223-229` → `st.design.row_boxes` `bars.lua:1193`. Combat `main.lua:1075-1077`. | every `st.*` call `type(...)=="function"`-guarded; teardown has no protected calls `main.lua:1072-1074` | none / none |
| Options | `main.lua:322` `set_opts` → `option_tables.lua:6647` → case dict → presets → funcs → info panel → top-level → bar-position → class options `generate_class_options_table` → `ST.class_opts_funcs[<CLASS>]` (6) `option_tables.lua:1586/3066/3786/4382/5103/5669`, dispatch guarded `:942` → hand panels. Registration `main.lua:325-331`. | every cross-module call `type(...)=="function"`-guarded; `class_hands` clobber defended `main.lua:105-111` | none; load order sound (`option_tables.lua` TOC 65 after `config_presets.lua` 63) |
| Diagnostics | login `main.lua:627-629` → `diag.report` `diag.lua:642` → per-section pcall → `print_line` `:104-112` → `pcall(print)`. Verbose: `main.lua:1785-1789` + `ST.print_runtime_diag` `:1721-1750`. Tick counters `main.lua:660-662` → `wrap_onupdate` `diag.lua:246`. Error ring `diag.lua:524` → chain → `record_error` `:495` → ring (cap 8) → `error_lines` `:589`. | every probe pcall'd; `read()` pcalls itself; output capped 85 lines `:607-632` | **MISSING LINK (F1)**: `install_error_handler` has no caller → "errors none" is a false negative |
| Latency | `LibLatencyMonitor` → `LATENCY_CHANGED` `main.lua:393` → `ST:LATENCY_CHANGED` `:883-896` → `set_adjusted_latencies` `:1406` → `set_gcd_times_before_swing_seconds` `:1430` → `get_gcd_marker_time_offset_seconds` `:1415` → `on_latency_update` `bars.lua:714-722` → `set_deadzone_width` `bars.lua:991-1017` | `:888-890` (llm_ready only on numeric world), `bars.lua:996-1000` (no divide by nil) | none; raw-vs-calibrated split is a documented rule |

---

## Per-client API truth table (cited from the in-repo `compat.lua` — see limitations)

Family detect `compat.lua:42-97`; interface fallback `:77-96`; `GetSpellInfo` global-id on Era/Wrath,
**name-based on TBC** `:160-176`; `GetSpellCooldown` name-query on TBC `:226-254`; `IsSpellUsable`
`:265-288`; `GetSpellPowerCost` `:296-304`; `GetSpellBaseCooldown` absent on Retail → (0,0) `:310-325`;
`IsCurrentSpell` `:332-336`; `IsSpellKnown` → `C_SpellBook.IsSpellKnown` / `…OrInSpellBook` `:183-216`
(`C_Spell.IsSpellKnown*` exists on **no** client); talents `:686-726`; `GetShapeshiftForm` (no `C_`
namespace on any client) `:733-747`; `UnitAura` `:456-488`; `UnitCastingInfo`/`UnitChannelInfo`
(9th vs 8th return = spellID) `:576-646`; `UnitPower*` `:345-398`; `UnitHealth*` `:406-434`;
`issecretvalue` `:152-154`; `C_Secrets.ShouldAurasBeSecret` `:552-566`; `C_EventUtils.IsEventValid`
used at `main.lua:532/546`, `hud.lua:646`, `swing_source.lua:57-60`; `PLAYER_TARGET_SET_ATTACKING`
registered classic-line only, **body unreachable (F2)** `main.lua:542-551`; `START/STOP_AUTOREPEAT_SPELL`
classic-line only `main.lua:528-541`; CLEU classic-line only `:1034-1058`; `PLAYER_SWING` Forever only
`swing_source.lua:1-13/57-60`; `GetTotemInfo` `:1060-1094`; `GetInventoryItem*` `:973-1032`;
`GetItemInfo`/`GetItemCount` `:1096-1180`; `GetWeaponEnchantInfo` 5th return `:1182-1205`;
`UnitGUID` `:1207-1223`; `UnitDistanceSquared` `:869-897`; `GetUnitSpeed`/`IsPlayerMoving` `:899-942`;
`CheckInteractDistance` `:846-867`; `IsSpellInRange`/`IsAutoRepeatSpell` `:782-844`; `IsMounted` `:804-810`;
`GetNetStats` `:962-971`; `GetCombatRating` `:944-960`; `GetSpellHaste`/`UnitSpellHaste` `:648-676`;
clock `:1225-1257`; `st.lust_supported` false on Era `:125-127`; `st.gcd_probe_spell_id` 29515 / 61304
`:110-113`; `LibClassicSwingTimerAPI` shipped only `_Vanilla/_TBC/_Wrath`; `LibClassicDurations` all 7
(pcall'd at `classes/paladin.lua:321-323`); `LibRangeCheck` all 7 (guarded internally).

## Justified exceptions (documented, intentional)

compat whole-entry secret degrade; unknown-client fallbacks (1.5 s cast time, zero-cost entry,
form 0); callback isolation `main.lua:798-829`; range-poll resilience `main.lua:1495-1573`;
per-tick isolation in bars/hud/nextaction_ui/practice_ui/rotationtext; practice start refusals
(14 messages, all printed + counted — **the pattern the rest of the addon should copy**);
HUD CLEU pcall; `pcall(LCD.Register…)` paladin (degrade is invisible to `/st diag` — see F5-style gap);
probe pcalls in swing_source/enemy_swing; raw `world_ms` in weave/twist math (documented rule).

## Positive findings

`compat.lua` is a genuinely professional cross-client layer (nil-safe, secret-guarded,
whole-entry degrade, "unknown ≠ zero" contract honoured by every caller); the 5-second init
deadline converts a stalled library into a terminal announced state; the inert swing stand-in
returns nil (not a plausible 1 s cycle) and paints an explicit "engine offline" label;
`run_guarded` paints the bar **before** the class hook so a throwing hook costs only its own
visuals; the guide flags `inputs_unknown` instead of rendering advice from stale reads;
`enemy_swing.lua` validates types and returns nil rather than guessing; load order verified sound
against all 17 `GetAddon` call sites.

## Limitations (stated by the auditor)

1. `/home/sam/wow-ui-source` was **not readable** from the hunter session (`permission.rejected:
   external_directory`, no shell/git tool) → the per-client API table is cited from the addon's own
   `compat.lua`, not `branch:file:line` from the client source. Rows the auditor could not
   independently re-verify are marked UNVERIFIED-HERE: `UnitDistanceSquared`, `GetUnitSpeed`/
   `IsPlayerMoving`, `CheckInteractDistance`, global `print`. **A dedicated cross-client truth pass
   against wow-ui-source is still owed** (F4 in particular against `classic_anniversary`).
2. No in-client verification — everything here is "verified offline".
3. The harness was not re-run by the auditor (orchestrator owns it).
4. The auditor had no write tools; the orchestrator filed this report.

## Operator decision needed

- **F6** — the base TOC advertising the whole interface matrix is a prior decision; fixing the
  load-throw hazard either narrows that advertisement or changes what the base TOC ships.
