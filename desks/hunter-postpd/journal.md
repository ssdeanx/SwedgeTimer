# hunter-postpd journal (filed by orchestrator — hunter has no write tools)

## 2026-10-19 — post-practice missing sweep (ses_eaa9dc4965ffevK3wn2AJ7goc1a)

Read-only, 14 files, 27 fallback locations. Prior N1-N4 + stable-files corpus excluded.

### HIGH (fix)
- H1: drill tick/cast paths bypass N4 isolation (practice_ui.lua:3554-3600s) — wrap in pcall+quarantine discipline.
- H2: clear_addon_state nil-wipes live GCD for rogue/druid (:3831-3877) — early-return hunter/shaman shape.
- H3: sync_to_addon else-branch stamps paladin seals + unguarded PALADIN (:3770-3779) — narrow + fail-closed.
- H4: key-drift falls back to paladin sim (:276-287 etc.) — fail-closed shaman shape for HUNTER/ROGUE/DRUID.
- H5: druid panel shows paladin icons but grades shifts — add druid_cast_order + def + label.
- H6: warrior_execute registered, no session seam; copy says Twist — ORCHESTRATOR RULING: report/live-log design stands (Execute grades live entries, no sim session), copy fixed to describe it honestly.
- H7: 5 class toggles + 2 setters nil-guarded not callable-guarded — copy warrior pattern.
- H8: 4 class post_init init calls unguarded — type(init)=="function" all six.
### MEDIUM (fix)
- M1: use_shaman_drill never calls accessor — compare key.
- M2: update_button no shaman branch (filed R3, still present).
- M3: ability_display_name no druid branch (lands with H5).
- M4: top-level page copy paladin-only + nil-unsafe gets — ORCHESTRATOR RULING: rewrite desc to enumerate all six drills + add `or` fallbacks.
- M5: reports undesignable + no combat guard — lockdown guard + 2 descriptors.
- M6: ROGUE_DEBUG probe at practice_ui.lua:3053 — delete.

### Verdict
VERDICT: FINDINGS 14. No CRITICAL.
