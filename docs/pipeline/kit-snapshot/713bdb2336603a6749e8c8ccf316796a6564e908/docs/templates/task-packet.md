# Task packet — <ID>: <title>

Self-contained: the implementer gets THIS FILE ONLY, no chat history.
A packet with unresolved `<placeholders>` fails the Stage 3 gate.

## Roles (fixed before code exists — no reviewer may equal the implementer)

| Role | Assigned |
|---|---|
| Implementer | |
| Criteria author | |
| Correctness reviewer | |
| Integration reviewer | |
| Waiver owner | Ben |

## Objective
One observable behavior. What exists after this packet that didn't before.

## Traceability
- Design requirement IDs: <REQ-…>
- Depends on packets: <IDs or none>
- Test spec: <path>
- Kit revision (from KIT.md): <sha>

## Context (minimum viable)
- Files in scope: <exact paths>
- Files explicitly OUT of scope: <paths — touching these fails review>
- Current behavior: · Desired behavior:
- Integration point: <where this meets the rest of the system>

## Constraints
- Smallest patch that satisfies the criteria; split triggers: >1 module
  boundary, >1 releasable behavior, not independently revertible, past the
  line budget (default ≤ ~300 changed lines).
- Match surrounding idiom. No new dependencies.
- Observability decision: failure signal to instrument = <signal>, or
  `N/A because <rationale>`.

## Acceptance criteria (criteria author)
Each maps to a requirement ID; each is mechanically checkable.
- [ ] <REQ-x: criterion with a number or exact observable>
- [ ] Tests: <named cases> — command: `<exact command>`, expected: <status>
- [ ] Build: `<exact command>`, expected exit 0
- [ ] Anti-gaming mutation: <the change that must make the tests fail>
- [ ] Manual-only gaps: <list, or none>

## Deliverable
Diff + run record at `docs/pipeline/evidence/<ID>-run.md` (base/head SHA,
diff digest, toolchain, commands, exit codes, test totals/skips, red + green
evidence) + self-report: done / not done / assumptions / confidence /
what evidence would change it. Unverified claims are NOT_RUN, not PASS.

## Review record
Consolidated at `docs/pipeline/evidence/<ID>-review.md` — reviewer
identities, head SHA, findings, verdicts (correctness / integration /
environment). Any post-review code change invalidates verdicts until
re-verified against the new SHA.
