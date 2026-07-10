# BOARD — pointer

The work queue. STATE.md holds the single next action; this holds everything
behind it. Move rows by cut/paste — every move is a commit.

Row format: `- [P-xx] title — owner (source)`

## Backlog (not yet packeted)

- [P-03] Test target + Swift↔Python frame round-trip golden test — implementer TBD (source: instance PIPELINE test plan)
- [P-04] Control-frame seq/ack + dedup over UDP — implementer TBD (source: STATE bodies-buried)
- [P-05] Deduplicate `pointer/` vs `pointer Mac/` receiver files — implementer TBD (source: STATE bodies-buried)
- [P-06] Latency benchmark: 50×50 px target, 2 s, 9/10 — Ben + implementer (source: standing PRD question)

## Ready (packet cut, criteria written, roles assigned)

## In progress

- [P-01] Per-hop frame counters + end-to-end latency log in `tools/mac_pointer_server.py` — packet not yet written; blocks routing the tracking bug (source: STATE next action)

## In review (evidence at docs/pipeline/evidence/)

## Blocked / waiting on [BEN]

- [P-02] Swift bake-off run (~evening; fixes implementer routing) — Ben ferries (source: kit ROLES.md)
- [P-07] CI install `ci/swift-xcode.yml` + action pinning — needs GitHub repo/runner decision (source: kit Stage 2 requirement)

## Done (since last milestone)

- 2026-07-10 Builds in Xcode confirmed — Ben
- 2026-07-10 Pipeline instance created — Fable

## Archive
