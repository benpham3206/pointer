# DESIGN — <project>

Date: · Author (Fable): · Reviewer (Sol): · Status: draft / reviewed / approved

## Architecture
Diagram (ASCII is fine) + one paragraph per component: responsibility, owner
module, what it must never do.

## Data flow
Source → transforms → sink, with formats and rates at each hop. Mark every
boundary where data can be **lost, duplicated, stale, or reordered** — each
mark needs a handling decision.

## Technology selection
| Choice | Selected | Rejected alternatives | Why | Reversible? |
|---|---|---|---|---|
One-way doors get an ADR (`adr.md`) and a [BEN] gate.

## Module / repo structure
Tree with one line per module. New code lands in exactly one place per
concern; if two places both plausibly fit, the structure is wrong.

## Requirement IDs
Every capability and constraint gets a stable ID (`REQ-001`…). Stage 3
packets and Stage 5 reviews trace back to these.

## Error handling & degradation
For each external boundary and user action: failure taxonomy, retryability,
user surface, and the **structured error payload** — every caught failure
produces at least `component`, `failure_type`, `root_cause` (safe text, no
secrets/raw sensitive payloads), plus a correlation ID for logs. Tests force
each failure class and assert those fields. Fail-closed vs fail-open decided
per class, not per mood.

## Platform matrix (Apple targets — mandatory; design fails review without it)
Each applicable row: owner, mechanism, and an automated check or named
manual scenario. No row may be blank for an applicable concern, and a
generic "Verified by" cell is a FAIL — manual scenarios name the physical
device, OS version, display topology, steps, and expected coordinates/state.

| Concern | Decision/mechanism | Verified by |
|---|---|---|
| Concurrency: actor/queue per mutable owner; callback executor; task cancellation owner; no detached lifetime without shutdown test | | |
| Lifecycle: foreground/background, wrist-down, termination, relaunch, sleep/wake; runtime entitlements actually relied on | | |
| CoreMotion: reference frame; timestamp clock domain (watch uptime ≠ Mac wall time); sequence numbers; reset; receiver stale/late/reordered algorithm | | |
| Permissions: Accessibility unknown/denied/granted/revoked state machine; prompt policy; recovery without restart; injection disabled while untrusted | | |
| Displays: ONE coordinate space end-to-end; AppKit↔CoreGraphics conversion; negative origins; **scaling + rotation**; reconfiguration/clamshell; cursor recovery after topology change | | |
| CGEvent injection: event source + tap choice; click-state sequencing (incl. double-click); reject non-finite and rate-abusive input; post-injection position read-back verification | | |
| Transport: disconnect/reconnect; stale handles/characteristics; duplicate control delivery; backpressure; session-generation fencing | | |

## Verification foundation (CI)
Stack CI template installed, placeholders replaced, hard-fail on
lint/typecheck/build/test/zero-tests, actions pinned to commit SHAs, one
green run recorded: check name = <…>, run URL/SHA = <…>.

## Logging & instrumentation
What is logged at each layer, in what structure, and the question each log
line exists to answer. Include the latency/health measurement path.

## Test strategy
Unit / integration / end-to-end split; what each layer can and cannot prove;
the manual acceptance matrix for anything hardware- or human-facing.

## Security & privacy
Data at rest/in flight, permissions requested and why, secrets handling
(never in the repo), threat sketch proportional to exposure.

## Sol review log
Loop until zero open blockers; the reviewer, not the author, closes a row.
| # | Finding | Severity | Resolution | Status | Evidence | Verified by | Verified at |
|---|---|---|---|---|---|---|---|

## Approval record (one-way doors)
| ADR | Decision | Artifact digest/commit | Ben's decision + date | Conditions |
|---|---|---|---|---|
