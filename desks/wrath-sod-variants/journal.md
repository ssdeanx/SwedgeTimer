# wrath-sod-variants — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fill Wrath + SoD variant gaps (druid/shaman Wrath rules, Stormstrike swipe, paladin SoD builds).
- **Scope:** classes/druid.lua, druid_guide.lua, classes/shaman.lua, shaman_guide.lua, classes/paladin.lua, nextaction.lua; bench rotation audits; wowsims/wotlk + sod sims.
- **Next step:** Read bench audits, fetch wotlk raw sims, write bench/wrath_sod_2026-10-19.md.

## 2026-10-19 — Verdicts filed
- **Worked on:** Read-only audit; fetched 11 wotlk raw sim files + sod retribution_test.go; wrote NEW bench/wrath_sod_2026-10-19.md (4 verdict sections).
- **Current state:** Done. Druid Wrath: spine MATCH, clip/DPE/FF/weave gaps cut-with-reason. Shaman Wrath: FE/FS/SR/MW5/SS/FS/Magma/ES/Nova/LL MATCH, LvB-gate holds, LS cut. Stormstrike swipe: TBC MATCH, SoD/Wrath fallback delta cut-with-reason (client ride covers). Paladin SoD: twist+Exodin MATCH, stack/shockadin/wrath-like cut-with-reason (own designs needed).
- **Next step:** Orchestrator validates (§5 method); no addon change owed.
- [signal:done] verdicts filed, validation owned by orchestrator.

## 2026-10-19 — Wrath leftovers closed (wotlk lane, research-only)

- **Worked on:** resumed desk; fetched 20 wotlk/sod/classic raw files this
  session (3 enhance APLs — closes the prior rate-limit gap — + SR/FE/LL/LvB/
  totems/FN/shocks/LB/LS/CoE + druid rotation/TF/SR/Berserk/Mangle + SoD 6s +
  Era 20s SS CDs); wrote NEW `bench/wrath_leftovers_2026-10-19.md`
  (glob-confirmed absent first; `wrath_sod` untouched). Verdicts: shaman F9 —
  SR-nil + ES-ungated keep, sub-5 WF-only filed, LS filed, SS CDs confirmed
  (Era 20 resolves the UNCONFIRMED note) cut-with-reason; druid — TF/Berserk/
  Bite/SR-durations/Mangle-value confirmed keep, clipRoar/Rake-DPE/FF/pooling/
  latency filed with exact values + needed inputs. CONFIRMED table (value +
  URL + applicability) + 12-item missing list (M1-M12, incl. UNFILED CoE
  observation M3 for triage). No addon edit, no git.
- **Current state:** done. Validation owner: orchestrator (§5 method in file).
- **Next step:** orchestrator validates + reconciles; in-client pass owns the
  UNCONFIRMED ledger (sets/glyphs/costs/ICD/CoE on 3.80.2).

## 2026-10-19 — [signal:done] wrath leftovers sourced + filed
- NEW bench file; 20 raw sim sources; CONFIRMED table + M1-M12 missing list.
  desks/wrath-sod-variants/.signals/20261019T160829Z.json
- Validation owner: orchestrator.

## 2026-10-19 — SoD paladin variants closed (sod-variants lane, research-only)
- **Worked on:** resumed desk; fetched sod retribution_test.go (6 Test funcs, 6 p8
  builds live, older phases commented out) + ALL SIX p8 APLs (twist 10510B, exodin,
  stack, shockadin-1h/2h, wrath — closes the prior "no APL fetched" gap) + builds
  dir + aura_mastery.go/holy_shock.go + 22 warcraftdb spell pages + SearxNG
  corroboration (wrath-like YT guides, shockadin reddit); wrote NEW
  `bench/sod_paladin_variants_2026-10-19.md` (ls-confirmed absent first).
- **Current state:** done. Twist/Exodin MATCH keep (Exodin seal-GAP now closed
  in-tree by followups lane; new LOW: Holy-Power stack input missing everywhere —
  grep-verified zero hits). Stack/shockadin-1h-2h/wrath-like: BUILD with APL
  citations + owed designs (dual-seal timers, spellpower/SoR plumbing, stack inputs,
  Templar/Sunlight/Aura-Mastery inputs). Wrath-alias CUT confirmed by APL.
  Item-name + 2H-"1.5"-quirk flagged UNCONFIRMED. gh_grep down (500), firecrawl unused.
- **Next step:** orchestrator validates (§9 method); no addon change owed.
- [signal:done] sod variants sourced + filed, validation owned by orchestrator.

## 2026-10-19 — SoD paladin variants BUILT (build lane, this session)
- **Worked on:** wired all three BUILD verdicts from bench/sod_paladin_variants_2026-10-19.md: seal-stacking (dual SoC/SoM 1 s timers + Judge dual-only + Naxx HW gate), shockadin (HS/AM 3-stack gates + Sunlight/Templar maintenance + Exo core), wrath-like (T2 Judge gate + Cons >1.5 s/or-stacks gate + Templar wait + DS fallback). Files: classes/paladin.lua (SoM 407798 latch, ERA-gated aura inputs, mode selection shock>wrath>stack>sod, HS/AM resolvers), nextaction.lua (3 orders + gates + maintenance + wait + fallback), tests +57/+55 pins. HS/AM slots FILED (guide_contract 8-slot pin holds; render follow-up owed); shock/wrath seal-maintenance primary role FILED (p8 primary UNCONFIRMED); Infusion 6 s + item names/roles FILED (no ids/names invented).
- **Current state:** done. Harness 38/0, luacheck 2/0 floor, guide_contract 853 green. Mutations kill: engine 8/8, gather 4/4 (on /tmp/opencode copies). Twist/Exodin untouched (MATCH, pins green).
- **Next step:** orchestrator validates (re-fetch §0 URLs, re-check cited lines, bash tests/run.sh). Render follow-ups (HS/AM slots, shock/wrath seal-maintenance primary) belong to nextaction_ui lane, not this one.
- [signal:done] sod variants built per APL with pins + filed items, validation owned by orchestrator.
