# ROLES.md — who does what, and why

Routing follows **measured performance, not model status**. Evidence lives in
`docs/MODELS.md` (dated, sourced). This table is provisional wherever a
bake-off hasn't run yet.

## The assignment rule

```
The best model at the language writes the patch.
The best model at finding bugs reviews the patch.
The best model at long-context coherence owns the architecture.
The cheapest competent model does boilerplate.
Author ≠ reviewer. No exceptions. Ever.
```

## Current routing (2026-07-10)

| Work | Model | Evidence (see docs/MODELS.md) |
|---|---|---|
| Architecture, design docs, pipeline ownership, integration review, large refactors | **Claude Fable 5** | Best repo-level coding (SWE-Bench Pro 80.3%) and *maintainable* agentic coding (FrontierCode Diamond 29.3% vs 13.4% next); proven codebase-scale coherence |
| Task specs, acceptance criteria, adversarial correctness review, CI/terminal debugging | **GPT-5.6 Sol** | Best agentic/terminal engineering (TerminalBench 91.9% > Fable 83.4%; SOTA OSWorld, BrowseComp); strongest rigor per token on review-shaped work |
| Bounded implementation patches — **provisional, pending Swift bake-off** | **Grok 4.5** | Near-frontier at ~$2/M in, ~4× fewer tokens per task, Cursor-trained on real dev sessions. **Caveat: hallucination rate ~54% — its output is never trusted unreviewed and it never reviews itself** |
| Boilerplate, docs cleanup, template/config maintenance, kit self-updates | **GPT-5.6 Terra** | Above GPT-5.5 peak at low cost; **measurably weak at code review (52.5% pass) — Terra never holds review authority** |
| Physical devices, taste, one-way doors, final run of build/tests | **Ben** | Only oracle with hands and a wrist |

## Transport

- **Fable** — this session (Claude Code).
- **Sol / Terra** — Codex bridge where possible, otherwise paste the packet
  into ChatGPT and paste the response back into the project's
  `docs/pipeline/inbox/` as `YYYY-MM-DD-<packet>-<model>.md`.
- **Grok 4.5** — launched from within Codex (Ben's setup), same inbox
  convention for outputs.

Packets in `packets/` are self-contained: any model can act on one with zero
conversation context. If a packet needs the chat history to make sense, the
packet is broken — fix the packet.

## Swift routing is conditional

Do **not** permanently lock "Grok writes Swift" until it survives the
bake-off (`bakeoff/`) on: Swift concurrency without racey
`@Published`/`@MainActor` mistakes, watchOS lifecycle, CoreMotion attitude
math, `CGEvent` quirks, Accessibility permissions, external-display
coordinates, reconnect/stale-packet handling.

Outcome table:

| Bake-off winner | Then |
|---|---|
| Grok 4.5 | Grok implements · Sol reviews correctness · Fable reviews integration |
| Sol | Sol implements + Grok adversarial-reviews ("find anything wrong; focus on Apple API misuse, lifecycle, threading, clamshell edge cases, simpler alternatives") · Fable reviews integration |
| Fable | Fable implements · Sol holds spec/test/review authority · Grok second-opinion reviews (Fable must not self-approve architecture *and* code) |

Runner-up becomes primary reviewer. Re-run the bake-off when any model
majorly updates, or after two consecutive milestones where the implementer's
patches needed rework.

## Per-packet assignment invariant (Sol finding #3, adopted)

Each task packet records `implementer`, `criteria_author`,
`correctness_reviewer`, `integration_reviewer`, and `waiver_owner` (always
Ben) **before code is written**. Hard gates:
`correctness_reviewer != implementer` and
`integration_reviewer != implementer`. If a default role owner implements,
the stack bake-off runner-up takes correctness review and the remaining
independent model (or Ben) takes integration review. The implementer never
arbitrates or waives findings on its own patch.

Stack routing is **pending** until a completed, blinded scorecard exists
(build logs, scorer identities, weighted totals, Ben's dated tie-break if
needed). "Provisional" is a planning label, not a gate result.

**Before a bake-off exists** (no runner-up yet): the packet assigns any
capable non-implementer as correctness reviewer and a second independent
model — or Ben — as integration reviewer. The hard inequality gates decide;
the default names don't.

## Escalation

- Reviewer and author deadlock → Fable arbitrates on architecture grounds
  **unless Fable is a party to the dispute — then Ben arbitrates**, with
  both positions attached as a Decision row.
- Any model touching a one-way door (publish, delete, spend, force-push)
  stops and asks. Reversible steps never wait for permission.
