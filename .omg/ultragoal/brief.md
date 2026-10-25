# Ultragoal Brief: SwedgeTimer v2.1.2 CurseForge Release Package

## Core Objective

Deliver the complete v2.1.2 CurseForge release package:

1. Ensure Cooldown HUD locking/relocking is responsive, and ensure Spec selection is mutually exclusive (only 1 spec selected at a time).
2. Add HUD Layout Template dropdown and live style controls into Design Mode options (`/st design`).
3. Implement Visual Brainstorming items:
   - Item 1: Animated Leading Edge Spark / Glow on the swing bar.
   - Item 2: Swing & Shot Completion Flash (tactile visual feedback pulse).
   - Item 3: Visual Theme Presets ("One-Click Modern Look" in options).
   - Item 5: Cooldown HUD Zoomed Icons (Clean Edge Mask cropping 5% Blizzard gray border).
4. Bump version to v2.1.2 across all TOC files, `main.lua`, `README.md`, and write complete `CHANGELOG.md` entry.
5. Verify 100% test pass rate via `bash tests/run.sh`.

## Architecture Boundaries

- Retain all 7 flavor TOCs; universal multi-client single build.
- No git commands allowed (standing desk rule in AGENTS.md).
- Preserve file line endings.
- New user toggles must ship nil-safe.
