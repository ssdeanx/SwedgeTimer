# forever-guide-ui — Journal

## 2026-11-05 — Desk opened (dispatching session)

- **Purpose:** close three confirmed defects in the WoW Forever guide/HUD surface and
  the amended Forever rogue poison name, with offline proof only.
- **Scope (hard):** `forever_guide.lua`, `hud.lua`, `nextaction_ui.lua`,
  `tests/forever_guide_state.lua`, `tests/forever_hud_gate_state.lua`,
  `tests/guide_contract.lua`, this desk. No `classes/*.lua`, no `compat.lua`, no
  `main.lua`, no TOC, no README/CHANGELOG, no `FG.SPELLS` id changes (except the
  ordered name-only change on `ENVENOM`), no git commands.
- **Contract:** the dispatch brief in the parent session (three evidence items +
  six ordered items + the scope amendment).

### Defects closed

1. **Reused output table never cleared** (`FG.evaluate`). `hold`, `hold_text`,
   `riding`, `filler_slot`, `judge_slot`, `waiting_judgement`, `inputs_unknown`
   were reset, but `action`, `spell_name`, `judge_call`, `rotation_key` were not.
   `nextaction_ui.lua:902-906` and every class provider hand the same table back on
   each tick, so HOLD/POOL/WAIT branches and new fights re-displayed the previous
   action and `judge_call` latched the Judgement icon forever.
2. **Forever HUD icons permanently hidden** (`HUD.create`). Every icon read
   `hud_show_<key>`, and the legacy per-class defaults ship `false` for
   `hud_show_holy_shield`, `hud_show_holy_strike`, `hud_show_lightningshield`,
   `hud_show_searing`, `hud_show_claw` — all five keys exist on the Forever slot
   sets (PALADIN 2, DRUID 1, SHAMAN 2), so those icons could never appear at any
   level.
3. **Restricted (secret) cooldown reads read as "ready"** — new compat contract:
   `api.GetSpellCooldown` gains a fifth return `restricted` (`true` only when the
   client returned secret timing and no readable fallback; nil elsewhere).
4. **Amendment — Forever poison name:** the client names it **Venom** (id
   1310703), the repo called it `Envenom`, so every name-based query was wrong.

### Changes (exact)

`forever_guide.lua`
- `:130` `ENVENOM = { name = "Venom", id = 1310703, ids = { 1310703 } }` (Lua key
  kept; no id change).
- `:270` `SPELL_KEY_BY_NAME["Venom"] = "envenom"` (replaces the stale `"Envenom"`
  entry, so the guide/HUD slot key stays `envenom` and nothing ripples).
- `:393-419` `get_hud_state`: captures the fifth return of both cooldown reads
  (name, then the `slot.spell` fallback), `restricted_state = restricted == true
  and dur <= 0`; `rem/dur` stay 0 when restricted.
- `:425` the GCD-echo block is skipped when `restricted_state` (a swipe that
  expires still reads "ready", so it is not shown either).
- `:512-515` `fg_hud_state_reused.restricted` cleared in the reset list, set `true`
  only on a restricted read (cannot latch).
- `:1329-1333` module-local `restricted_seen = false` (declared above
  `live_cooldown`, documented).
- `:1340-1345` `live_cooldown` captures the fifth pcall return; `restricted == true`
  sets `restricted_seen` and returns `nil` (unknown), never 0.
- `:1501-1522` `FG.evaluate` clears `action`, `spell_name`, `judge_call`,
  `judge_slot`, `filler_slot`, `rotation_key` (the first two were missing), keeps
  the `hold`/`hold_text` reset untouched, and resets `restricted_seen`.
- `:1541-1543` at the end, `restricted_seen` ORs into `out.inputs_unknown` (the
  caller's bit is preserved, never cleared).
- `:1064-1066` `is_known(inputs, "Venom", "envenom_known")` and
  `out.spell_name = "Venom"`; `out.action` stays `"envenom"`.
- Zero occurrences of `"Envenom"` remain in the file.

`hud.lua`
- `:611` `icon.show_key = (st.family == "FOREVER" and "hud_forever_show_" or
  "hud_show_") .. usable[i].key` (plus a 5-line comment explaining the collision).
  This is the only hud.lua code change; non-Forever families keep the exact legacy
  key (`tests/hud_state.lua`'s `hud_show_*` pins still pass unchanged).

`nextaction_ui.lua`
- **No change needed/desired.** Its M6 path already suppresses advice on
  `out.inputs_unknown == true` (`:638-639`), which is exactly the contract the
  restricted flag feeds. Editing it would have been scope creep.

### Tests

`tests/forever_guide_state.lua` (148 → **172 checks**)
- Reuse block: one `reuse` table, tick 1 cues `judge` (+`judge_call`), tick 2 is a
  prot WAIT branch → asserts `action`/`spell_name`/`judge_call`/`judge_slot` are
  nil, `hold`/`hold_text == "WAIT"` survive, `rotation_key == "prot"` lands, and an
  unknown class clears `action`/`rotation_key` (pins every newly cleared field).
- Restricted block: stubbed `api.GetSpellCooldown` returning `0,0,0,0,true` →
  `out.inputs_unknown == true`; returning 4 values → `false` and still `judge`
  (classic shape unchanged); caller's `inputs_unknown = true` preserved.
- Venom pins: `FG.SPELLS.ENVENOM.name == "Venom"`, id unchanged,
  `FG.SPELLS_BY_NAME["Venom"] == FG.SPELLS.ENVENOM`, stale `"Envenom"` absent,
  guide slot key `envenom`, HUD slot key `envenom`, evaluator emits
  `action == "envenom"` + `spell_name == "Venom"`. The one pre-existing Envenom
  name assertion was updated (it was asserting the wrong client name); no spell-id
  assertion was touched.

`tests/forever_hud_gate_state.lua` (107 → **144 checks**)
- Per-class `HUD.create` loop: every icon reads `hud_forever_show_<key>` and none
  reads a legacy `hud_show_<key>`.
- Collision block: the five legacy-collision keys all exist on the Forever slot
  sets, each still ships `= false` in `config_presets.lua`, and no
  `hud_forever_show_<key>` default ships (nil = shown).
- Restricted `get_hud_state` block: `remaining/duration == 0` even with a live
  tracked GCD (no invented swipe, GCD echo included), `restricted == true`,
  no desaturate/text; next readable read has `restricted == nil` (no latch) and a
  readable duration; a restricted flag *with* a readable duration keeps the flag
  clear and still swipes.

`tests/guide_contract.lua` — **unchanged**: it pins the shared `nextaction` /
class-provider contract, never `FG.evaluate`, so there was no stale reuse pin to
update. Re-run green (1059 checks).

### Validation (exact)

```
lua5.1 tests/forever_guide_state.lua      PASS (172 checks)          exit 0
lua5.1 tests/forever_hud_gate_state.lua   144 checks, 0 failed; PASS  exit 0
lua5.1 tests/guide_contract.lua           PASS (1059 checks)         exit 0
luacheck forever_guide.lua hud.lua nextaction_ui.lua <3 tests>   0 warnings / 0 errors, exit 0
```

Regression guards also run (green, unchanged): `forever_guide_gate_state` (7),
`hud_state` (859), `wiring_check` (901/0), `nextaction_state` (659),
`real_wire_state` (1016/0), `rogue_state` (1137), `paladin_state` (1319),
`warrior_state` (2186), `hunter_state` (2046), `shaman_state` (1083),
`druid_state` (1777). Full harness NOT run (per dispatch).

### Mutation proofs (16/16 killed, `/tmp/opencode/mut` copy, `python3 /tmp/opencode/mutate.py`)

Baseline copy green (172 / 142 at the time), post-restore green. Each mutation is a
literal revert of one production change, `exit != 0` plus the expected FAIL line:

| # | mutation | FAILs |
|---|---|---|
| M1 | `out.action = nil` commented out | 4 |
| M2 | `out.judge_call = nil` commented out | 3 |
| M3 | `out.spell_name = nil` commented out | 2 |
| M4 | `out.rotation_key = nil` commented out | 2 |
| M5 | `restricted_seen` never folded into `inputs_unknown` | 2 |
| M6 | `live_cooldown` no longer flags restricted | 2 |
| M7 | `get_hud_state` ignores the flag | 3 |
| M8 | GCD echo invented on a restricted read | 2 |
| M9 | `restricted` not reset (latches) | 2 |
| M10 | `get_hud_state` never sets `restricted` | 1 |
| M11 | spell definition back to `"Envenom"` | 4 |
| M12 | slot-key map back to `"Envenom"` | 3 |
| M13 | evaluator emits `"Envenom"` | 2 |
| M14 | evaluator queries `"Envenom"` | 3 |
| M15 | HUD icons back on `hud_show_<key>` | 12 |
| M16 | readable duration still marked restricted | 1 |

**Known survivor (honest):** `live_cooldown`'s `return nil` → `return 0` under
`restricted == true` passes the whole suite (probed explicitly). No rule
distinguishes nil from 0: `is_ready()` treats both as ready, and the protection is
the `inputs_unknown` flag (pinned). The nil is the ordered contract and the correct
"unknown" value, but it is not observable through the current public surface.

### Filed out of scope (do NOT silently absorb; each needs its own lane)

1. **`classes/rogue.lua` Forever name paths.** `GUIDE_SPELL_NAMES.envenom =
   "Envenom"` (`:186`), `resolve_named_spell("player:envenom", "Envenom")`
   (`:1033`), `utility_ready(..., "Envenom")` (`:1221`), the row label (`:2496`).
   Forever HUD slots carry `spell = id`, so `:314` is not reached, but
   `:1033`/`:1221` still ask the client for the wrong name on Forever. The moment
   the rogue lane touches these, it must use `"Venom"` on Forever only.
2. **`envenom_usable` is never published by the live gather** (repo-wide grep: only
   the FG rule and the test reference it). The Forever Venom branch therefore stays
   unreachable in live play (5 CP falls through to Rupture) even with the name
   fixed. Pre-existing, not a regression from this lane — needs a rogue-gather
   follow-up (`classes/rogue.lua` was out of scope).
3. **`option_tables.lua` HUD slot toggles** write `db["hud_show_" .. slot_key]`
   (`:601`, `:2315`, `:2380`). After the Forever namespace change those toggles no
   longer drive the Forever icons (they were already ineffective — the icons were
   pinned hidden by those very `false` defaults). The options lane must key by
   family (`hud_forever_show_` on Forever).
4. **Forever HUD render of `state.restricted`.** The provider now reports it, but
   `hud.lua`'s renderer does not read it (only the single show-key edit was
   permitted). Until a render lane lands, a restricted slot renders as idle rather
   than "unknown".
5. **`classes/{paladin,shaman,warrior,rogue}.lua` direct `hud_show_<key>` reads**
   (paladin `:4449`, shaman `:3998`, warrior `:5181`, rogue `:552`) are class-side
   display mirrors, untouched; if any of those slots is also a Forever slot it will
   read the wrong namespace after this change.
6. **`classes/rogue.lua:929`** builds its display `out.inputs_unknown` from
   `raw.unknown` / `inputs.inputs_unknown` and overwrites the FG-set bit — so a
   restricted read does not suppress the rogue guide (paladin threads it at
   `classes/paladin.lua:3958`; druid/hunter/shaman/warrior pass the caller's table
   straight through and are fine). Needs a one-line rogue-lane fix.

### UNVERIFIED

- The real fifth-return shape on a Retail/Forever client (secret/restricted
  timings) cannot be observed offline; the code is defensive (`restricted == true`
  only, nil elsewhere). Compat has not landed the fifth return yet — until it does,
  `restricted` is always nil here and this lane behaves exactly as before.
- In-client appearance (icons now actually visible on Forever, no taint/secure-
  frame complaint from the new key) needs the operator's client session.
- Whether `hud_forever_show_<key>` collides with any other saved setting: grepped,
  no producer exists today.

### State / next step

Landed and proven offline. Blocked on nothing in this lane. The six filed items
above need their owning lanes; the operator's in-client pass is the only remaining
check for appearance.
