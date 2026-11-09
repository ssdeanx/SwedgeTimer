# Brief — Forever HUD secret/cooldown/GCD API contract (2026-11-08)

## Role and mode

Read-only research lane for the Lead's Agent Team. You do **not** edit product files,
tests, the TOC, config, docs, or the reference repos. You write exactly one bench
report, one desk journal, and one done signal.

## Mission

Produce a citation-backed API contract for **WoW Forever only** (Camelot client,
`origin/forever`, version.txt `1.60.1.70790`, commit `eac30af59`) that tells the
implementer exactly how a tainted addon may display cooldown swipes, countdown text,
and the global cooldown while the client's cooldown data is secret in combat and
instances, and exactly how cached values must be handled.

The operator's words: "everything that is secret in wow forever is correctly passed
the data so it does not become tainted. especially if something is cached, that will
cause problems because data cant be tainted and it will be without a check for it."
"The cooldowns must be fully working with global cooldown and cooldowns in
combat/dungeons." "Enterprise grade quality."

## Source discipline

- Primary source: `/home/sam/wow-ui-source`, read-only. Use
  `git -C /home/sam/wow-ui-source show origin/forever:<path>` and
  `git -C /home/sam/wow-ui-source grep -n <pattern> origin/forever -- <path>`.
  Never check out, edit, or run git in `/home/sam/SwedgeTimer`.
- Secondary: `/home/sam/SwedgeTimer` (read-only), `/home/sam/SuperSwingTimer-WoW`
  (read-only) only if it shows a working pattern.
- No web search. No other directories.
- Cite every claim as `origin/forever:<path>:<line>` and quote the annotation or the
  Blizzard call site. A remembered fact is a rumour: mark it UNCONFIRMED.

## Questions that must be answered with evidence

### A. When is cooldown data secret?

1. Read `SecretPredicateAPIDocumentation.lua` and `SecretPredicatesDocumentation.lua`.
   Enumerate the exact `C_Secrets` predicates relevant to the HUD:
   `HasSecretRestrictions`, `ShouldCooldownsBeSecret`,
   `ShouldSpellCooldownBeSecret(spellIdentifier)`, `ShouldActionCooldownBeSecret`,
   `GetSpellCooldownSecrecy`, `ShouldAurasBeSecret`, `ShouldSpellAuraBeSecret`.
   State the argument shape and the `true` only answer.
2. Explain the `SecretWhenCooldownsRestricted` annotation text verbatim and the
   restriction states it names (combat, encounter, challenge mode, PvP match,
   addon-restricted maps). Determine whether Forever applies it to the player's own
   spells in dungeons/raids, and whether per-spell `NeverSecret`/`AlwaysSecret`
   overrides can make a spell readable even under restrictions.
3. State the practical consequence: at what moments do `C_Spell.GetSpellCooldown`,
   `C_Spell.GetItemCooldown`, `C_ActionBar.GetActionCooldown`, and
   `GetInventoryItemCooldown` return secret fields, and which fields are secret.

### B. The sanctioned addon display path (the core question)

Read these generated docs in full:

- `Blizzard_APIDocumentationGenerated/SpellDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/LuaDurationObjectAPIDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/DurationTextBindingObjectAPIDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/DurationUtilDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua`
- `Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua`

Answer, with the exact annotation lines:

1. `C_Spell.GetSpellCooldown` vs `C_Spell.GetSpellCooldownDuration`:
   - Which one is `SecretWhenCooldownsRestricted`?
   - Is the returned `LuaDurationObject` itself a secret value, or an opaque
     non-secret handle whose values may be secret? Evidence: missing
     `SecretWhenCooldownsRestricted` on the return, `HasSecretValues`,
     `SetCooldownFromDurationObject` usage, Blizzard call sites.
   - Which `LuaDurationObject` methods may a tainted addon call when
     `HasSecretValues()` is true, and which must never be called? Check
     `GetRemainingDuration`, `GetTotalDuration`, `GetStartTime`, `IsZero`,
     `IsActive`, `HasStarted`, `HasExpired`, `HasSecretValues` and their
     `SecretArguments` annotations.
2. `CooldownFrame:SetCooldownFromDurationObject(duration, clearIfZero)`:
   - Quote `IsProtectedFunction` and `SecretArguments`.
   - Does `SecretArguments = AllowedWhenUntainted` forbid passing an opaque
     duration object from tainted code, or only literal secret values? Find
     conclusive evidence. Look at `Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua`
     around line 603 and `Blizzard_AuraButton.lua` around lines 160-180 for how
     Blizzard builds/passes aura duration objects.
   - Same question for `DurationTextBinding:SetDuration`, `SetFontString`,
     `SetEnabled`, `SetUpdateInterval`; `StatusBar:SetTimerDuration`; and
     `FontString:SetText` / `Frame:SetAlphaFromBoolean` (quote the
     `AllowedWhenTainted` annotations).
3. Countdown text:
   - `C_DurationUtil.CreateDurationTextBinding` and its full configuration
     surface; how to attach a binding to the HUD's existing font string; which
     formatter APIs exist (`AbbreviatedNumberFormatterAPIDocumentation.lua`,
     `NumericFormatterAPIDocumentation.lua`, `SecondsFormatterAPIDocumentation.lua`);
     whether a tainted addon can create/configure a formatter.
   - `CooldownFrame:SetHideCountdownNumbers`, `SetMinimumCountdownDuration`,
     `SetCountdownFont`, `SetCountdownFormatter` — which are safe from tainted
     code, and whether the frame's own countdown numbers are secret-safe.
4. GCD:
   - Does `C_Spell.GetSpellCooldownDuration(gcd_probe_spell_id, false)` return the
     running GCD as a duration object? Check `C_Spell.GetSpellCooldown`'s
     `SpellCooldownInfo` and `C_ActionBar.GetActionCooldownDuration` too.
   - Propose a concrete GCD strategy that never reads a secret number:
     pass-through duration object on the active icon, or a native
     `CooldownFrame` driven by it. State exactly how the HUD knows the GCD is
     running without `GetRemainingDuration`/`GetTotalDuration`.
   - What can `LibGlobalCooldown` keep doing (`calculate_expected_spell_gcd`,
     `SPELL_UPDATE_COOLDOWN`, cast events) and what must it stop caching when
     restricted?
5. Trinkets/items:
   - Is there any duration-object API for item cooldowns on `origin/forever`
     (`C_Spell.GetItemCooldown`, `GetInventoryItemCooldown`, `C_Item`,
     `C_Container`)? If not, what is the legal face for an equipped on-use
     trinket while its cooldown is restricted? Confirm the existing
     `api.GetInventoryItemCooldown` fourth-return contract is still correct.

### C. Secret-value cache rules (the operator's specific worry)

1. Read `FrameScriptDocumentation.lua` for `scrubsecretvalues`, `scrub`,
   `secretwrap`, `secretunwrap`, `securecopy`, `settablesecurity`; quote
   `SecretArguments`, `HasRestrictions`, `ReturnsNeverSecret`.
2. Read `Blizzard_CooldownViewer/CooldownViewerSecure.lua` and
   `Blizzard_AuraContainer/Blizzard_AuraContainerGroups.lua` for the
   `settablesecurity` + `secretunwrap` table pattern (`DisallowSecretKeys`,
   `DisallowTaintedAccess`). Explain what it protects and whether an addon can
   use the same pattern for its own caches.
3. Produce a **cache hazard matrix** for the existing SwedgeTimer HUD path:
   - `hud.lua`: `HUD.known_names`, `known_cache`, `HUD.layout_cache`,
     `HUD.icons[i]` fields (`cd_start`, `cd_duration`, `text_value`, `tint`,
     `desaturated`, `texture_key`), `HUD.trinkets[13/14]` fields,
     `TRINKET_STATE`, `PREVIEW_STATE`.
   - `LibGlobalCooldown.lua`: `gcd_duration`, `gcd_started`, `gcd_expires`,
     `current_spell_gcd`, `current_spell_haste`.
   - `compat.lua`: `api.GetSpellCooldown`, `api.get_cooldown_remaining`,
     `api.GetInventoryItemCooldown`, `api.UnitAura`, `api.IsSpellUsable`,
     `api.GetSpellInfo`, `api.is_spell_known_state`.
   For each: what could be secret, where it is stored, whether a later tick can
   read it without a check, and the exact minimal fix (drop, scrub, revalidate,
   or store only an opaque handle).
4. State the rule the implementer must test: no secret value may enter a plain
   table (key or value), a string, a comparison, arithmetic, or a formatter; a
   cached entry must be proven plain before use, or the cache must be cleared.

### D. Design recommendation

End with a decision table the implementer can follow:

| HUD need | API to call | Allowed from tainted? | Secret-safe sink | Cache rule | In-client check |
|---|---|---|---|---|---|

Cover: ability cooldown swipe, countdown text, GCD swipe, GCD text suppression,
trinket on-use cooldown, restricted-unknown face, desaturation, glow/mana/range
tints. Mark every row UNCONFIRMED if it rests on runtime behaviour that only the
client can prove.

## Deliverable

`bench/forever_hud_api_2026-11-08.md`

Structure:

1. Scope and source commit.
2. Restriction states and predicates.
3. Cooldown read matrix (API, annotations, secret moment, returns).
4. Duration-object pass-through verdict, with every annotation quoted.
5. Countdown text verdict.
6. GCD verdict and proposed wiring.
7. Trinket/item verdict.
8. Secret-value cache matrix for the six cache groups above, with minimal fixes.
9. Decision table (D).
10. In-client test checklist with exact `/run` probes and expected observations.
11. UNCONFIRMED register.

Also leave `desks/forever-hud-api/journal.md` and
`desks/forever-hud-api/.signals/<timestamp>.json` (done/checkpoint/blocked).
Read `desks/journal.md` tail and `bench/lessons.md` first; do not re-search
answered questions.

## Hard constraints

- **WoW Forever only.** No classic/TBC/Wrath/Retail proposal. Any design must be
  gated on Forever + API probes so every other client is byte-identical in
  behaviour.
- No product edits. No git in `/home/sam/SwedgeTimer`. No version changes.
- Do not guess an annotation, an ID, or a runtime behaviour. Cite or mark
  UNCONFIRMED.
- Enterprise-grade: exact file:line, no vacuous statements, no "probably".
