# Brief — SuperSwingTimer aura icon reference and SwedgeTimer port map (2026-11-08)

## Role and mode

Read-only research lane for the Lead's Agent Team. You do **not** edit product files,
tests, the TOC, config, docs, or the reference addon. You write exactly one bench
report, one desk journal, and one done signal.

## Mission

Extract the exact implementation recipe for the **WoW Forever-only** per-class
buff/debuff icon row in `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua`,
and map it onto a new SwedgeTimer module that draws the same kind of icons **above
the top swing bars for each class**, without reading secret aura data and without
changing any non-Forever client.

The operator's words: "check how it uses unitauras for buffs/debuff icons, and can
we implement the same thing for our that will go above the top bars for each
class." "Also the aura thing should be wow forever only." "Do not break any other
clients. Enterprise grade quality."

## Source discipline

- Primary: `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua` (read-only).
  Also read its `WIRING.md` section 7 and the aura-related parts of
  `SuperSwingTimer_UI.lua` if the anchor/lifecycle crosses files.
- Target: `/home/sam/SwedgeTimer` (read-only for you).
- API confirmation: `/home/sam/wow-ui-source`, `origin/forever` (read-only git show).
- No web search. No other directories. Never edit the reference addon or SwedgeTimer.

## SuperSwingTimer code map to extract

Read and report the exact mechanics, with `file:line` citations:

1. **Support/secrecy gates** (around lines 1-120, 137-200):
   `HasAuraContainerSupport` (`C_AuraContainerUtil`, `AuraContainerSortMethod`,
   `AuraContainerSortDirection`), `IsAuraDataSecret`
   (`C_Secrets.ShouldAurasBeSecret()`), `GetSpellAuraSecrecy` /
   `IsSpellAuraReadable`, `GetForeverPlayerAura` (the `C_UnitAuras` reader that
   returns nil instead of reading a secret field), `ns.IsSecretValue`.
2. **Spell lists** (lines ~326-620): `FOREVER_STANCE_SPELLS`,
   `FOREVER_BUFF_SPELLS` (per class), `FOREVER_DEBUFF_SPELLS` (per class),
   `FOREVER_NEW_ABILITY_CANDIDATES`, `FOREVER_SHARED_BUFFS`,
   `FOREVER_RACIAL_BUFFS`, the `AppendUnique` merge rules, and the comments about
   TBC-only / non-aura IDs. Copy the **per-class lists** into your report
   (class -> ids), preserving the comments that mark why each id is there.
   Explicitly mark every id that is TBC/SoD-only, a non-aura candidate, or
   unverified for Forever. Do not silently drop the comments.
3. **Container creation** (lines ~683-1060): `AURA_FRAME_STRATA`,
   `PROC_MAX_DURATION`, `CreateAuraContainerFrame` (the exact
   `CreateFrame("AuraContainer", ..., "CustomAuraContainerTemplate,
   DisableUntrustedLayoutScriptsTemplate")` fallback),
   `CreateAuraGroupContainer` (unit token, filter string, `includeSpellIDs` set,
   `SetEnabled`, `SetUnit`, `AddAuraSlot`, `SetAuraGroupLayout`,
   `SetSize`, `SetFrameStrata`, `Show`/`Hide`, eligibility), `BuildAuraSpellIDMap`,
   `StyleAuraButton` (bar/cooldown/text options), and the exact filter for
   own-caster debuffs (`HARMFUL` plus `includeSpellIDs`; report whether
   `PLAYER` / `COMBAT_LOG_EVENT_UNFILTERED` is needed to keep own-caster only).
4. **Anchor/lifecycle** (lines ~752, 1038-1060, 1403-1450, 1489-1775):
   `GetAnchorBar`, `ComputeIconYOffset`, `ApplyContainerAnchors`,
   `IsDebuffRowPopulated`, the throttled `UpdateForeverAuraIcons` (0.15 s), the
   init retry on `PLAYER_LOGIN` / `PLAYER_ENTERING_WORLD`, the "never read a secret
   height" rule, and the hand-over between classic icon groups and the native row.
5. **What is Forever-only and what is shared**: identify every branch on
   `ns.isForever` / `ns.hasAuraContainer` / `IsAuraDataSecret()` so the port cannot
   accidentally run on classic clients.

## API confirmation

Verify the exact `origin/forever` contracts used by the reference and report them:

- `Blizzard_AuraContainer` templates: `CustomAuraContainerTemplate`,
  `CustomAuraButtonTemplate`, `DisableUntrustedLayoutScriptsTemplate`.
- `C_AuraContainerUtil` and the sort enums; `C_Secrets.ShouldAurasBeSecret`,
  `ShouldSpellAuraBeSecret`, `ShouldUnitAuraIndexBeSecret`,
  `ShouldUnitAuraInstanceBeSecret`.
- `UnitAura` / `C_UnitAuras.GetAuraDataByIndex` /
  `C_UnitAuras.GetPlayerAuraBySpellID` annotations (`SecretWhenAurasRestricted`,
  `RequiresUnitAuraAccess`, `RequiresNonSecretAura`).
- `includeSpellIDs` semantics (a set keyed by spell id) and whether
  `AddAuraSlot` vs `AddAuraGroup` is the right call for a fixed per-class row.

## Proposed SwedgeTimer port

Map the reference onto the target stack, without writing code:

1. New module `aura_icons.lua`, loaded in `SwedgeTimer.toc` in dependency order
   after `hud.lua` (or state the correct position), with a guarded init seam from
   `main.lua` `post_init` (or an own event frame; state which and why).
2. **Forever-only gate**: `st.family == "FOREVER"` plus `C_AuraContainerUtil`
   plus sort-enum plus `CreateFrame` template probe. On every other client the
   module must be inert: no frame, no event registration, no aura scan, no
   option side effects. State the exact gate expression.
3. Per-class lists: `AURA_ICONS_BUFFS[class]`, `AURA_ICONS_DEBUFFS[class]`,
   shared/racial merge at container creation only; six classes
   (WARRIOR, ROGUE, DRUID, SHAMAN, PALADIN, HUNTER). Explain what to do for a
   class with no list (inert) and for a non-Forever client (inert).
4. **Anchoring above the top bars**: use the existing
   `ST:iter_hands()`, `ST:get_anchor_frame(hand)`,
   `ST:get_hiding_anchor_frame(hand)`, `ST:get_bar_frame(hand)` APIs
   (`bars.lua:939-966`). Compute the topmost *visible* bar from plain frame
   geometry and anchor the aura row's bottom to that bar's top; re-anchor when
   the top bar changes, when bars are dragged/resized/shown/hidden, and on
   `PLAYER_ENTERING_WORLD`. Never read a secret height/size. Do **not** propose
   editing `bars.lua` unless a public helper is genuinely missing; if it is,
   specify the minimal additive helper and route it to the Lead as a follow-up,
   not a unilateral edit.
5. **Options/defaults**: propose the exact `config_presets.lua` keys
   (`aura_icons_enabled`, `aura_icons_show_debuffs`, `aura_icons_size`,
   `aura_icons_spacing`, `aura_icons_grow`) and the `option_tables.lua` control
   placement, following the nil-safe rule (`== false` hides; document the
   Forever default; no default-visible change on classic clients).
6. **Tests**: list the state-suite cases needed (stubs for the container, sort
   enums, `C_Secrets`, `CreateFrame`, bar frames; per-class list selection;
   includeSpellIDs sets; secret gate; non-Forever inert; anchoring; toggles) and
   the mutation proofs that would catch a regression.
7. **Risks**: list every place where the SuperSwingTimer approach depends on
   its own global namespace or frame, and how to avoid a copy-paste dependency.

## Deliverable

`bench/aura_row_reference_2026-11-08.md`

Structure:

1. Scope and reference commit/time.
2. Reference code map with `file:line` citations (support gates, lists, container,
   anchor, update, hand-over).
3. Per-class spell-id tables with provenance markers.
4. API confirmation table (`origin/forever` citations).
5. Proposed `aura_icons.lua` port plan (module skeleton, gates, lists, container
   config, anchor, lifecycle, TOC/main/config/options, tests).
6. Do-not-copy list (reference-namespace assumptions, TBC-only IDs, etc.).
7. UNCONFIRMED register + in-client checklist (container creation, visibility,
   top-bar anchoring, per-class icon content).

Also leave `desks/aura-row-reference/journal.md` and
`desks/aura-row-reference/.signals/<timestamp>.json`. Read `desks/journal.md`
tail and `bench/lessons.md` first; do not re-search answered questions.

## Hard constraints

- **WoW Forever only.** The aura row is inert on every other client. No
  classic-scope proposal, no default-visible change outside Forever.
- No product edits. No git in `/home/sam/SwedgeTimer`. No version changes.
- Do not guess an id, a template name, or an API annotation. Cite or mark
  UNCONFIRMED.
- Enterprise-grade: exact file:line, complete class tables, no omitted comments
  that change the meaning of an id.
