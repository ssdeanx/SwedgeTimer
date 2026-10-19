# lessons

earned once, written here, never argued away. newest last.

- **briefs live in files, not prompts.** long prompts can abort mid-flight
  ("This text request is too large"), and a lane in `error, unreconciled`
  state cannot be revived. write the brief to `bench/briefs/`, verify
  it exists, point the lane at it. (2026-10-17)
- **never gate on `st.is_mainline` alone.** the WoW Forever client is
  mainline-code but must behave like classic-line where swing features are
  concerned — gate on swing activity instead. (2026-10-17, cross-engine)
- **a remembered id is a rumor.** confirmed = the source said it and the
  citation is on the bench (`bench/verify_bank.md` is the working
  example); otherwise UNCONFIRMED, in caps. (2026-10-17)
- **enumerate the tool catalog before scraping.** firecrawl exposes 28
  tools; agents used two because the brief said two. enumerate, then pick
  per job. (2026-10-17)
- **no default-visible change without an explicit gate.** new toggles ship
  nil-safe: `== false` hides, nil = off, defaults documented for the
  options pass. (standing)
- **the operator owns git.** desks never run version-control commands;
  all changes stay in place and stated. (standing)
- **every lane lists every file it changed.** mid-wave, SwedgeTimer.toc's Interface line changed (120100→120105) with no scoped owner — three lanes observed it, none owned it. observers did self-report; the changer didn't. reconcile restores test+matrix state and logs the ambiguity for the owner. (2026-10-17)
