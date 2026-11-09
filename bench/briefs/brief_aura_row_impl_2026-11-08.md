# Brief — WoW Forever-only aura icon row implementation (2026-11-08)

## Role and mode

Implementer lane for the Lead's Agent Team. You own the files below and no others.
Write code, red-first tests, mutation proofs, one bench report, one desk journal,
and one done signal.

## Mission

Add a per-class **buff/debuff icon row above the top swing bars**, using the native
Forever `AuraContainer` / `AuraButton` system the way
`/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua` does. It must be
**WoW Forever only**: on Classic Era, TBC Anniversary, Titanforge, Retail, and any
other client the module is completely inert (no frame, no event, no aura scan, no
option side effect, no visual change).

The operator's words: "check how it uses unitauras for buffs/debuff icons, and can
we implement the same thing for our that will go above the top bars for each
class." "Also the aura thing should be wow forever only." "Do not break any other
clients. Enterprise grade quality."

## Required reading, in order

1. `bench/aura_row_reference_2026-11-08.md` — the research lane's port map, class
   lists, gate expressions, and API citations. If it is absent or incomplete,
   stop and report; do not guess the template or the ids.
2. `AGENTS.md` (Cross-engine, Gotchas, Workshop mechanics), `desks/journal.md`
   tail, `bench/lessons.md`.
3. `hud.lua` header (layout/reflow/combat rules), `bars.lua:939-966` (hand/frame
   helpers), `main.lua` `post_init` (guarded init seam), `SwedgeTimer.toc`
   (single authoritative load order), `tests/toc_check.lua`,
   `config_presets.lua` `ST.class_defaults`, `option_tables.lua` shared HUD
   section.

## Write scope (exact)

- NEW `aura_icons.lua`
- NEW `tests/aura_icons_state.lua`
- `SwedgeTimer.toc`
- `main.lua` (init seam only; do not restructure init)
- `config_presets.lua` (defaults only)
- `option_tables.lua` (the aura-row controls only)
- `option_table_presets.lua` (only if the chosen options need a preset entry)
- `tests/run.sh` (register the new suite)
- `tests/toc_check.lua` (only if the single-TOC coverage pins require it)
- `bench/aura_row_2026-11-08.md`
- `desks/aura-row/**`

Do **not** touch `hud.lua`, `compat.lua`, `LibGlobalCooldown.lua`,
`classes/*.lua`, `tests/hud_state.lua`, `tests/forever_secret_compat_state.lua`,
`tests/secret_guard_state.lua`, `docs/`, `README.md`, `CHANGELOG.md`, or any
version field. No git.

## Work items

### 1. Forever-only gate (non-negotiable)

- `st.family == "FOREVER"` **and** `C_AuraContainerUtil` present **and** the sort
  enums present **and** the `CreateFrame("AuraContainer", ..., <template>)` probe
  succeeds. If any gate fails: no frame, no event registration, no aura read, no
  options side effect, silent no-op.
- Never gate on `st.is_mainline` alone (the Forever client is Mainline-code but
  other Mainline clients must stay untouched).
- Add a test that loads the module on every simulated non-Forever family
  (ERA / TBC / WRATH / CATA / MISTS / RETAIL as available in the harness) and
  proves zero frames, zero event registrations, zero `UnitAura` /
  `C_UnitAuras` / `C_AuraContainerUtil` calls.

### 2. Native aura containers (secret-safe)

- Create one native container for **player buffs** (`HELPFUL`, unit `player`)
  and one for the **player's own target debuffs** (`HARMFUL`, unit `target`,
  own-caster filter; follow the reference's exact filter and the T2 report's
  own-caster finding).
- Use `includeSpellIDs` sets built from the per-class lists, merged with the
  shared buffs and the player's own racial list at container creation only. The
  class lists stay pure.
- Do not read `AuraData` fields (`name`, `icon`, `applications`, `duration`,
  `expirationTime`, `sourceUnit`, `spellId`, ...) in addon code. The client fills
  the native buttons. Do not call `UnitAura` / `C_UnitAuras.GetAuraDataByIndex` /
  `GetPlayerAuraBySpellID` when `C_Secrets.ShouldAurasBeSecret()` is true.
- A guarded classic fallback is optional only if the T2 report shows it is
  needed for Forever; if not, keep the module native-only. Never add a classic
  fallback that can run on non-Forever clients.

### 3. Per-class lists

- Six classes: WARRIOR, ROGUE, DRUID, SHAMAN, PALADIN, HUNTER. Copy the
  Forever-specific lists from the T2 report, preserving the provenance comments
  and excluding any id the report marks TBC/SoD-only or unverified.
- A class with no list -> module inert for that class (no empty frame left
  visible). Fail closed: a missing list never shows another class's auras.
- Add a test per class that pins the exact `includeSpellIDs` set (including the
  shared/racial merge) and proves no cross-class leak.

### 4. Placement above the top bars

- Anchor the aura row's bottom to the top edge of the **topmost visible swing
  bar** for the current class, using the existing public helpers:
  `ST:iter_hands()` (`main.lua:132`), `ST:get_anchor_frame(hand)`,
  `ST:get_hiding_anchor_frame(hand)`, `ST:get_bar_frame(hand)`
  (`bars.lua:939-966`).
- Determine the topmost bar from plain frame geometry only. Re-anchor when:
  the top bar changes, a bar is dragged/resized/shown/hidden, the aura row's
  size changes, and on `PLAYER_ENTERING_WORLD`. Throttle the maintenance pass
  (the reference uses 0.15 s).
- Never read a secret height/size/offset. Frame geometry of addon-created bars is
  plain; if any read can be secret, probe first and skip the re-anchor.
- Do not edit `bars.lua`. If a public helper is genuinely missing, stop and report
  the minimal additive helper to the Lead instead of editing outside scope.

### 5. Options and defaults

- Add config keys (names may be adjusted to match the T2 report):
  `aura_icons_enabled` (Forever default **on**, documented in `config_presets.lua`),
  `aura_icons_show_debuffs` (default on), `aura_icons_size`,
  `aura_icons_spacing`, `aura_icons_grow` (row direction). All nil-safe:
  `== false` disables; nil follows the shipped default.
- Add the controls to the shared HUD options section, with the same
  `name`/`desc`/`get`/`set`/`hidden` quality as the existing HUD options. Do not
  put a non-Forever-visible control on classic clients (hide the group when
  `st.family ~= "FOREVER"`).
- Do not change any existing default for classic clients.

### 6. TOC / init wiring

- Add `aura_icons.lua` to the single `SwedgeTimer.toc` in dependency order
  (after `hud.lua`; verify the correct position against `toc_check.lua`). No new
  flavor TOC. No duplicate module line.
- Wire initialization from `main.lua` `post_init` through the existing guarded
  seam pattern (`st.guard.run` or an equivalent pcall/one-time notice) after the
  bars exist; a module that throws must cost only the aura row, never the rest
  of init. A missing module in an offline sandbox stays a no-op.
- Register the new suite in `tests/run.sh` in the correct section; keep the
  harness output format.

### 7. Tests (red-first, mutation-proven)

`tests/aura_icons_state.lua` must simulate the client surface and prove:

- Forever gate creates the containers exactly once; a second init is a no-op.
- Non-Forever families (ERA/TBC/WRATH/CATA/MISTS/RETAIL) are inert: no frames,
  no events, no reads.
- Missing `C_AuraContainerUtil` / sort enums / template -> silent no-op, no throw.
- Per-class `includeSpellIDs`: exact ids, shared/racial merged only at container
  creation, no cross-class leak, all six classes.
- Secret gate: when `C_Secrets.ShouldAurasBeSecret()` is true, no aura data read
  is attempted; when false, the chosen fallback (if any) is used.
- Anchor: topmost visible bar selection (ranged vs mainhand vs offhand), hide
  fallback to the next visible bar, re-anchor on bar change, throttle behaviour.
- Options: `aura_icons_enabled == false` hides without destroying frames; nil
  follows the Forever default; classic clients see no group.
- TOC: module present exactly once in load order; `toc_check` stays green.
- Combat: creation never happens in combat lockdown; a deferred init retries and
  then succeeds; a failed creation retries later without a latch.

Mutation proofs: at least three single-line reversions on isolated `/tmp` copies
(e.g., remove the Forever gate, drop the secret gate, anchor to the wrong bar),
record exact failure counts/exit codes, restore the copies.

## Deliverable

`bench/aura_row_2026-11-08.md` with:

1. What changed, file by file, with line references.
2. Gate expression and lifecycle diagram (init -> containers -> anchor -> update).
3. Per-class id tables actually shipped, with provenance.
4. Test evidence: suite count, full `bash tests/run.sh` step/fail, luacheck, luac.
5. Mutation table.
6. UNCONFIRMED in-client items and the exact `/run` probes to close them
   (container creation, visibility, top-bar anchoring per class, icon content).

Also `desks/aura-row/journal.md` + `.signals/<timestamp>.json`.

## Hard constraints

- **WoW Forever only.** Zero behavior change on every other client. Every new
  frame/event/read is behind the gate above.
- Never read secret aura data; native containers only.
- No git, no version bump, no docs/README/CHANGELOG edits, no `bars.lua` or
  class-file edits.
- Enterprise-grade: exact evidence, mutation proofs, no vacuous tests, no `_`
  silencing, no lint-config changes, LF preserved.
