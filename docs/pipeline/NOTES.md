# NOTES — pointer (agent journal)

Append-only scratch for ANY model working this project. Bugs spotted outside
your packet, friction, wins, lessons, ideas, honest venting. Raw capture for
the retro — an unwritten observation is one the kit never learns.

Format: `- YYYY-MM-DD · <model> · #tag — note (file:line if relevant)`
Tags: `#bug` `#friction` `#win` `#lesson` `#idea` `#vent`

Rules: append only, never groom · out-of-scope bug = one line here + a
BOARD Backlog row, then back to your packet · venting allowed, be specific ·
at retro every entry is harvested or explicitly skipped.

---
- 2026-07-10 · fable · #bug — "tracking unreliable" (Ben) is currently unroutable: four candidate layers, zero counters. P-01 exists because of this entry.
- 2026-07-10 · fable · #lesson — BLE and relay transports share the exact same frame bytes by design; any tracking bug that differs between transports is therefore transport-layer, not filter/mapping. Cheap discriminator, use it first.
