# Audit All Classes — Journal

## 2026-10-22 — Desk opened
- **Purpose:** RELEASE AUDIT, all six classes (hunter, shaman, paladin, rogue, warrior, druid) — every one verified, none taken on trust from prior lanes; re-prove prior fixes with own legs.
- **Scope (write):** classes/hunter.lua, classes/shaman.lua, classes/paladin.lua, classes/rogue.lua, classes/warrior.lua, classes/druid.lua, rogue_guide.lua, nextaction.lua, weave.lua, twist.lua, hunter_ui.lua (readers only) + owning suites. Lib untouched (HU-29). No main.lua/bars.lua/compat/swing_source/hud/options/practice/run.sh/Libs/TOCs/versions.
- **Standard:** in-game behavior only. Era = spell ID, Anniversary = spell NAME, separate legs per class. HU-31: classic line only (Era/Anniversary/Titanforge); Retail/Forever on own paths. HU-15: is_spell_known binary + is_spell_known_state seam. HU-22: lazy-bars enabled-AND-in-use.
- **Next step:** systematic payload-path sweep (id-vs-name) per class + spell-known/leveling gates, then owning suites, mutations, fixes, report.
