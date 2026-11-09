# bench/shaman_slots_2026-10-19.md — the shaman slotless lines taught: S-19 / S-17 closed, S-20 filed

Desk: `shaman-slots`. Date: 2026-10-19. Spec: `bench/shaman_drills_2026-10-19.md` §2
(the filed S-17 / S-19 / S-20 rows) + `bench/class_features_drills_2026-10-19.md`
§2.6 A (the shaman feature checklist). Validation owner: **orchestrator**.

**Scope (orchestrator-fixed):** `classes/shaman.lua`, `shaman_guide.lua`,
`tests/shaman_state.lua`, `tests/shaman_guide_state.lua`, `tests/guide_contract.lua`
(shaman sections only), `tests/hud_state.lua` (shaman census only). NOTHING else — no
`practice*.lua`, `option_tables.lua`, `config*.lua`, `main.lua`, `diag.lua`,
`compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, TOCs, versions, README/CHANGELOG/docs,
no other classes, no git, no lint-config.

---

## 1. What shipped

### 1.1 The guide slots (15 → 17)

| Slot | Key | Id | Swipe | Rule | Feed |
|---|---|---|---|---|---|
| 16 | Lightning Shield | 49281 (UNCONFIRMED) | none (a buff with charges, not a cooldown) | **11b** (between Fire Nova 11 and Lava Lash 12) | `inputs.lightningshield_due` — the player's own shield aura |
| 17 | Searing Totem | 10438 (UNCONFIRMED, the Forever sim's) | none (a persistent totem) | **9b** (between Stormstrike 9 and Magma 10) | `inputs.searing_down` + `inputs.fight_elapsed` + `inputs.mw_observed` |

**Rule 11b (Lightning Shield, S-19).** `st.family == "WRATH" and
inputs.lightningshield_due == true`. The audit's citation: "the three
wowsims/wotlk enhancement APLs + `lightning_shield.go` (maintain iff inactive, above
Lava Lash) - audit 2026-10-19 §2.6 S-19". WRATH-only: the Era/TBC sims run no
Lightning Shield.

The read is free — the player's aura walk already looks for the Lightning / Water
Shield auras (the charge row), so the maintain rides that answer. Tri-state:
`true` = due (the walk ran and NO shield aura is up), `false` = a shield aura is up
(nothing to do — a **Water Shield build never sees the prompt**, because its own
aura is up), `nil` = unknown (the walk has not run, or the client may hide auras →
`api.auras_may_be_secret()`) → never prompts.

**Rule 9b (Searing Totem, S-17).** `st.shaman_guide.get_searing_upkeep_due(st.family,
inputs.fight_elapsed, inputs.searing_down, inputs.mw_observed)` — the audit's pure
predicate (it was practice-surface-only; it moved up into the rule matrix so the live
guide and the D-S4 drill grade **one** gate). ERA-only (Era-base 20 s, SoD 30 s);
the TBC low-mana fallback (S-25) quotes no threshold and the Forever static maintain
(S-27) is filed, so no other family fires it — no number is invented.

The Searing feed is **known-gated** like every other maintain in this module (the
Fire Elemental — itself a talent — carries the same gate): the Searing Totem is a
talent on Era/SoD, so a player without it must never be prompted. The probe asks for
the **client's own resolved id** (the shipped 10438 is the Forever sim's and never
resolves on the classic-line clients); an unknown id answers false, so the feed stays
silent rather than prompting on a guess.

### 1.2 The icon resolution (the ids are UNCONFIRMED)

Both ids are the audit's, and the Searing id is a **modern** id (the Forever sim's) —
it does not resolve on the classic-line clients at all. So `resolve_guide_icons`
re-points both slot icons from the **client's own spell data by NAME** (the name is
certain where the id is not; the classic `GetSpellInfo` answers a name query with the
spell's id in its 7th return — the `resolve_named_spell` convention). The HUD row's
two mirrors re-point the same way (`resolve_hud_slot_icons`), and on TBC the HUD icon
resolves by NAME (a bare id leaves it blank there — the name-vs-id rule,
`bench/lessons.md`).

### 1.3 The HUD mirror (where a live read exists)

`ST.SHAMAN.HUD_SLOTS` 8 → 10: the two maintain mirrors are declared **before** the
self-served trinkets (the trinkets stay last). Both are display-only (no cooldown to
ride → `HUD_SKIP_GCD` carries them) and both **hide unless their `hud_show_<key>`
toggle reads exactly true** — nil = off (the HUD treats a nil toggle as wanted, so
the provider-level hide is the no-default-visible gate; the druid Claw shape). The
upkeep cue is the glow: it lights while the cast / drop is needed, in combat (the
Stormstrike "ready" rule). An unknown read (an unrun aura walk / an unreadable fire
slot) draws nothing, and the Searing mirror carries the **same known gate** as the
guide (a player without the talent is never cued).

The row's geometry is unchanged: the two mirrors are provider-hidden, so the
effective icon count stays six (`tests/hud_state.lua` pins the width at
`6 * 36 + 5 * 2`).

### 1.4 The rotation table's `live` flags now match reality

| Line | Before | After |
|---|---|---|
| `searing` (S-17) | `live = false` | **`live = true`** (slot 17 + rule 9b) |
| `lightningshield` (S-19) | `live = false` | **`live = true`** (slot 16 + rule 11b) |
| `coe` (S-20) | `live = false` | `live = false` (**filed**, below) |

The practice surface rides the same slots and rules, so the scenario step now teaches
both new lines (`PRACTICE_REASONS` + the two new ctx mappings: `cooldowns.searing` →
`searing_down`, `cooldowns.lightningshield` → `lightningshield_due`, and
`resources.mw_observed`).

---

## 2. Filed (with the exact blocker / probe)

| Item | Verdict | The exact blocker / probe a build lane needs |
|---|---|---|
| **S-20 Call of the Elements (66842)** | **FILED** — no slot, no rule, `live = false` | The Wrath APLs rank CoE iff the **water totem** is under 20 s, but **no water-slot clock exists in-tree**: only `WEAVE_TOTEM_AIR_SLOT = 4` and `WEAVE_TOTEM_FIRE_SLOT = 1` are read (`classes/shaman.lua`), there is no water constant, no `refresh_water_from_totems` reader, no gather feed and no engine input. The probe a build lane needs: (a) a **water-slot `GetTotemInfo` reader** (`WEAVE_TOTEM_WATER_SLOT = 3` by FrameXML analogy — **UNCONFIRMED** against the client's own FrameXML), in the fire-slot reader shape (`refresh_water_from_totems` → `(empty, holding)`); (b) the gather feed `inputs.water_remaining` / `inputs.water_duration`; (c) the engine input spec + a rule ranked **above Magma** per the APL spine; (d) a guide slot `{key = "coe", spell_id = 66842}` + the contract pin + the HUD mirror + the options widget; (e) **in-client confirmation of 66842 on 3.80.2** (does `GetSpellCooldown` answer? does the water-slot read report? does the re-drop cost a GCD?). The id is **UNCONFIRMED**; the APL rank is still owed by the CoE triage (the audit quotes no index, so the rotation table lists the line last). |
| **The `hud_show_lightningshield` / `hud_show_searing` defaults + the options widgets** | filed (the options pass) | `config_presets.lua` (the SHAMAN defaults block) and `option_tables.lua` are **out of this lane's scope**. The mirrors are declared and hidden until their toggle reads exactly true, so the defaults should ship **`false`** (the druid Claw shape: `hud_show_claw = false`). Without a default the HUD treats the slot as wanted (`hud.lua:770` hides only on `== false`) — the provider-level hide still keeps the row's geometry at six shown slots, but the options pass should own the default + the widget. |
| **The Lightning Shield / Water Shield choice (S-29)** | filed (unchanged) | The audit defers it: "the Shield choice needs mana awareness". The maintain only fires while **no** shield aura is up, so a Water Shield build is never prompted — but a Water Shield player who has not yet cast their shield would see the LS prompt once. The spec-option read is owed a lane. |
| **The in-client id confirmations** | owed (the in-client pass) | Lightning Shield 49281 (Wrath), Searing Totem 10438 (the Forever sim's id — the classic-line clients answer by name instead), and the `IsSpellKnown` behaviour for a **totem talent** (the Searing gate's probe). |

---

## 3. UNCONFIRMED carried by this lane

| Item | Where | Why |
|---|---|---|
| Lightning Shield 49281 (Wrath) | the guide slot + the HUD mirror | the audit's S-19 id; the slot icon resolves from the client's own data by name, so a wrong id only affects the fallback |
| Searing Totem 10438 | the guide slot + the HUD mirror | the audit's S-17 id — the **Forever sim's** id; the classic-line clients resolve it by name instead |
| `IsSpellKnown` on a totem talent (the Searing gate) | the gather's known gate | the Fire Elemental (a Wrath talent) carries the same gate, so the shape is proven in-tree; the Searing Totem's own answer is still owed an in-client pass |
| The water-slot constant (3) | the CoE filing | FrameXML analogy only — never read in-tree |

---

## 4. Validation

- **Harness:** `bash tests/run.sh` → **41 steps / 0 failed** at this lane's close,
  `luacheck .` → **2 warnings / 0 errors** (the standing floor; the two KEEP-ruled
  warnings are pre-existing and in files this lane never touched). The lane's own six
  files are luacheck **0/0**.
  (A later run shows **41 / 1 failed** — `tests/druid_state.lua` (the druid energy-shift
  grade). That is the parallel **druid** lane's mid-edit: `classes/druid.lua` changed at
  22:03 during this lane's close, and the druid suite loads none of this lane's files
  (`compat` / `utils` / `druid_energy` / `druid_guide` / `classes/druid` / `practice`) —
  the standard crossfire the orchestrator reconciles.)
- **Suites:** `tests/shaman_guide_state.lua` **1378 checks PASS** (the pure rule
  matrix, the provider contract, the gather feeds, the practice surface and the
  rotation table), `tests/shaman_state.lua` **663 PASS** (the class-side view),
  `tests/guide_contract.lua` **1031 PASS** (the new shaman section), `tests/hud_state.lua`
  **668 PASS** (the shaman census).
- **The guide contract is per class:** the shaman's own section (§7) was added; the
  paladin's and the rogue's sections are untouched (the only shared edits are two
  additive `SPELL_INFOS` fixtures and the `SHAMAN = {}` sandbox table entry).
- **Mutation proofs:** 18 mutations on `/tmp/opencode/shaman-slots-mut` copies
  (`mutate.sh` + `m13.py`), **18/18 killed, 0 void** — the LS family gate, the LS
  unknown-hides, the Searing family gate, the 20 s boundary, the Searing unknown
  slot, the gather's family gate, the inverted shield read, the SoD latch, the
  rotation `live` flag, the dropped slot, the HUD nil=off gate, both icon
  resolutions, the rule rank swap (LS above Lava Lash), the practice reason, the
  practice writer's coverage, the Searing known gate (the guide's and the HUD
  mirror's). The repo tree was byte-identical to the pre-mutation copy afterwards
  (verified per file).
- **No default-visible change:** the two guide slots are invisible until their rule
  fires (the frame stacks one icon per slot at the frame's centre and fades in the
  active one); the two HUD mirrors hide until their toggle reads exactly true, and
  the row's geometry stays at six shown slots.

---

## 5. What was NOT done (and why)

- **No practice / options / config / engine change** — the shared engine registers
  the drills; the options pass owns the new toggles' defaults and widgets.
- **No CoE build** — no water-slot clock exists; the exact probe is filed above
  (faking it would prompt on a guess).
- **No S-29 (the shield choice)** — the audit defers it; the maintain only fires
  while no shield aura is up.
- **No change to `weave.lua`, `practice*.lua`, `hud.lua`, `bars.lua`, `compat.lua`,
  `main.lua`** — out of scope.
- **No git, no lint-config change, no version bump** — the operator owns those.
