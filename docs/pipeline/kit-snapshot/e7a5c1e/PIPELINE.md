# PIPELINE.md — idea → shipped, with receipts

Owner: **Claude Fable 5** (architecture + long-context coherence).
Rigor authority: **GPT-5.6 Sol**. Revision 3 — Sol's re-verification
findings (6 blocking, 1 should-fix; inbox:
`2026-07-10-sol-pipeline-reverification-sol.md`) applied, plus absorptions
from the ~/.hermes mining pass (`2026-07-10-hermes-mining-sol.md`).
Status: **NOT RATIFIED** — a fresh independent Sol pass must verify this
revision; per the evidence contract, a review does not approve its own fixes.

Every stage has an **artifact** and a **gate**. No artifact, no next stage.
Gates marked **[BEN]** are human decisions — one-way doors never get walked
through by a model alone.

## Evidence contract

A gate is `PASS`, `FAIL`, `NOT_RUN`, or `WAIVED`; **silence is never PASS.**
Every gate record names the artifact revision or git SHA, actor, timestamp,
exact check, result, and evidence path. Command evidence includes the command,
toolchain/environment, exit code, test totals, skips, and produced artifact.
Manual evidence includes device, OS, configuration, steps, observed result,
and Ben's dated verdict.

The implementer cannot review, waive, or arbitrate a finding on its own
patch. A model cannot cast a gate on an artifact it authored. Only Ben
approves one-way doors and waivers. Gate evidence and waivers live under
`docs/pipeline/evidence/`; inbox files are inputs, not approvals.

**Waivers:** only Ben may grant one. A waiver records finding ID, severity,
affected version, risk, compensating control, owner, expiry/revisit trigger,
and Ben's dated approval. Blocking security, data-loss, permission-bypass, or
release-integrity findings cannot be waived into an automated public release
— fix them or pull the feature.

## Proportionality — the fast path

The full pipeline is for demanding, multi-session, or user-facing work. Don't
run a release checklist on a one-file reversible tweak — that's the pipeline
getting in the way, which is itself a defect (file it in the retro).

A change may take the **fast path** (implement → one review → done) when ALL:
reversible in one `git revert` · no new dependency, permission, network
surface, or schema · no public/deploy effect · single module · covered by
existing CI. Author ≠ reviewer still holds. When in doubt, not fast-path.

Fast-path evidence is one STATE.md row containing: eligibility result for
every condition above, exact commit SHA, CI check URL/status for that SHA,
independent reviewer identity/date/verdict, and rollback command. Missing
fields are `NOT_RUN`. The fast-path artifact is that row plus the reviewed
diff; its gate is eligibility `PASS` + CI `PASS` + independent review `PASS`.

## Stage 0 — Idea → Decision row

An idea is not a directory. It enters as a decision row **on the pre-project
board** (Hermes STATE / wherever Ben reads decisions — not a project
STATE.md, which doesn't exist yet): one atomic question with a number in it,
kill criteria written before build criteria.

- **Artifact:** the board row, plus Ben's recorded yes (date + wording).
- **Gate [BEN]:** yes → the directory is created → Stage 1.

## Stage 1 — PRD

Two intake modes:

- **Vague idea** (the normal case — pointer started this way): run a
  brainstorming pass (skill: `superpowers:brainstorming` — one question at a
  time, options with a recommendation) until the atomic question, kill
  criteria, and thinnest chain exist. Then fill `docs/templates/prd.md`.
- **Existing PRD** (cathedral-class documents included): the document is
  Stage 1 *input*, not the PRD. Compress it: extract the atomic question,
  kill criteria, and the thinnest chain that closes a loop (well-written ones
  contain their own v0 — use it). The original is filed as reference; mine it
  for requirement IDs at Stage 2. A 900-line PRD is a quarry, not a contract.

- **Artifact:** PRD with success metric, kill criteria, non-goals, and an
  approval record: artifact digest/commit, Ben's decision, date, conditions.
- **Gate [BEN]:** PRD approved, recorded in the PRD itself.

## Stage 2 — Design + verification foundation

Fable authors `docs/pipeline/DESIGN.md`. It assigns **stable requirement
IDs** and specifies architecture, data flow, module ownership, failure
taxonomy, structured error payloads (`component`, `failure_type`,
`root_cause`), degradation, observability, security, and test boundaries.
Every one-way door has an ADR with Ben's dated approval bound to the reviewed
revision.

**Product design (user-facing projects):** before or alongside DESIGN.md,
fill `docs/templates/ui-spec.md` — visual identity (3 direction cards when
identity is vague: reference points, type, color, motion; Ben picks one),
screen inventory, interaction states (empty/loading/error included), and
platform idiom. Skills: `frontend-design` / `design-taste-frontend` for
direction, `paper-desktop:design-to-code` when a Paper design exists,
`dataviz` for any charts. UI acceptance criteria come from this spec —
"looks good" is not a criterion; "matches direction card §3, all states
present" is.

**Apple targets** additionally include the platform matrix — each applicable
row names its owner, mechanism, and an automated check or named manual
scenario (template in `docs/templates/design-doc.md`): actor/queue +
cancellation ownership per mutable owner; app/watch lifecycle incl.
wrist-down, termination, relaunch, sleep/wake, runtime entitlements;
CoreMotion reference frame, timestamp clock domain (watch uptime ≠ Mac wall
time), sequence/reset/staleness semantics; Accessibility state machine
(unknown/denied/granted/revoked) with recovery; one display coordinate space
+ explicit conversions, negative origins, reconfiguration, clamshell;
transport disconnect/reconnect, stale handles, duplicate delivery,
backpressure, session-generation fencing. The matrix also specifies the
CGEvent injection contract — event source/tap choice, click-state
sequencing, rejection of non-finite/rate-abusive input, and post-injection
read-back verification. Display cases include scaling and rotation. Every
manual lifecycle/display scenario names the physical device, OS, topology,
steps, and expected coordinates/state.

**CI is installed here, not at release.** Copy the stack template from
`ci/`, replace every placeholder, make lint/typecheck/build/tests hard-fail,
pin third-party actions to reviewed commit SHAs, and run it once on the repo.
Record the required check name and green run URL/SHA. Stage 6 consumes CI;
it must not introduce it.

Stage 2 CI evidence additionally includes **five negative canaries** run
against the installed workflow — a type error, a failing test, zero
collected tests, a missing required formatter/linter, and an unresolved
placeholder — each failing non-zero, followed by a clean green run on the
same workflow revision. A skipped required job is `NOT_RUN`, never `PASS`.

Sol reviews the exact DESIGN.md revision (`packets/sol-pipeline-review.md`).
Fable resolves; **Sol verifies each resolution** — repeat until no blocking
finding is open. The review log carries status, resolution evidence,
verified-by, verified-at. Open should-fixes are fixed, descoped, or
Ben-waived.

- **Artifact:** DESIGN.md + ADRs + platform matrix + ui-spec (if user-facing)
  + verified review log + configured green CI.
- **Gate:** Sol-verified zero open blockers; CI green on the reviewed
  revision; **[BEN]** approvals recorded for every one-way door.

## Stage 3 — Decomposition

Fable creates task packets (`docs/templates/task-packet.md`). Each packet
contains: requirement IDs; one observable behavior; exact in/out-of-scope
paths; dependency packet IDs; current and desired behavior; integration
point; **implementer, correctness reviewer, integration reviewer** (no
reviewer equals the implementer — hard gate); exact build/test commands with
expected status; manual-only gaps; the test-spec path.

Sol supplies acceptance criteria and tests (`packets/sol-task-spec.md`)
covering zero, boundary, malformed, stale/late/reordered,
disconnect/reconnect, permission-denied/revoked, and double-delivery cases
where applicable. Failure tests assert the structured payload fields and
absence of secrets. Every criterion maps to a DESIGN requirement ID. Every
packet names an anti-gaming mutation that must make its tests fail.

Split a packet if it crosses more than one module boundary, contains more
than one independently releasable behavior, cannot be reverted
independently, or is projected past the agreed line budget. Time estimates
are planning data, not gate evidence.

- **Artifact:** dependency-ordered packets + test specs + role assignments.
- **Gate:** no unresolved `<placeholders>`; every design requirement maps to
  a packet or an explicit non-goal; exact commands + expected results
  present; reviewer/implementer separation valid.

## Stage 4 — Implementation loop

The assigned implementer takes one packet. Before editing, record the base
SHA and run the packet's checks. Add the specified behavior tests and
capture the deliberate **red** result. Apply the smallest patch that
satisfies the criteria. Add observability only where the packet names a
failure signal; otherwise record `N/A` with rationale. No new dependencies;
no files outside the packet's scope.

Anything you notice outside the packet — a bug, a smell, a friction, a
better idea — goes to `docs/pipeline/NOTES.md` (one line) and, if
actionable, a BOARD.md Backlog row. Never fix it mid-packet.

Write `docs/pipeline/evidence/<packet>-run.md`: base/head SHA, diff digest,
dirty-tree state, toolchain versions, exact commands, timestamps, exit
codes, test totals/skips, red evidence, green evidence, CI run URL, artifact
paths. Skipped or absent tests are `FAIL` unless Ben waived them in the
packet. Self-report claims without evidence are `NOT_RUN`.

Before handoff: **reread every distinct path you created or edited**,
end-to-end, fix what you find, then run the final verification pass. The
diff you reviewed is the diff you ship. (Absorbed from
hermes-execution-todo.)

- **Artifact:** bounded diff + tests + run record + self-report.
- **Gate:** local checks and required CI green on the exact head SHA; every
  criterion evidenced; no out-of-scope file or unresolved placeholder.

## Stage 5 — Independent review

Roles were fixed in the packet before coding. If a default role owner
implemented, use the named alternate; **never** let a model review or
arbitrate its own patch.

1. **Correctness reviewer** (`packets/adversarial-review.md`): checks every
   criterion, reruns high-risk and anti-gaming tests, audits
   platform/lifecycle/concurrency/error paths, records findings against the
   exact head SHA.
2. **Integration reviewer** (`packets/fable-integration-review.md`, or the
   alternate when Fable implemented): module placement, boundaries, idiom,
   trajectory, changed ground truth — same SHA.
3. **Real-environment run** — Ben or CI. Hardware/UI claims require Ben's
   device, OS, configuration, steps, observations; CI cannot substitute for
   a physical-only claim.

**Optional convergence pass (high-risk packets):** commission independent
attempts from two models plus a refuter pass; only claims/approaches that
survive refutation proceed to review. Use for security-sensitive,
data-loss-adjacent, or architecturally irreversible packets — not routinely.

Evidence consolidates in `docs/pipeline/evidence/<packet>-review.md`:
identities, SHA/digest, findings, commands + exit codes, manual matrix,
evidence paths, three explicit verdicts. A code change after review
invalidates prior verdicts until the reviewer re-verifies against the new
SHA. Deadlocks: Fable arbitrates on architecture grounds **unless Fable is a
party — then Ben arbitrates.**

- **Artifact:** completed review record bound to the candidate SHA.
- **Gate:** correctness PASS + integration PASS + human/environment PASS; no
  open blocker; every other finding fixed or validly waived (by Ben only).

## Stage 6 — Release

Stage 6 packages and publishes the already-reviewed SHA; CI exists since
Stage 2. Create `docs/pipeline/releases/vX.Y.Z.md`: reviewed SHA, completed
regression/release/security checklists, CI run links, artifact names +
SHA-256 checksums, signing/notarization evidence, rollback command, Ben's
smoke-test result. **Commit this record before tagging.**

The release workflow fails closed if: placeholders remain; the tag doesn't
resolve to the reviewed SHA; the release record is absent; a required check
isn't green; an expected artifact is absent/empty; a checksum differs; or
required signing/notarization/stapling verification fails. Publish actions
are pinned to reviewed commit SHAs and run only in a protected environment
requiring Ben's approval.

Deploy targets are ADR-recorded per project (web → Vercel/Netlify previews +
prod; backend → Fly/Docker deployed by CI on tag; Apple → TestFlight or
notarized artifact). Never deploy from a laptop.

- **Artifact:** committed release record + CI-built verified artifacts.
- **Gate [BEN]:** Ben approves the protected release environment for the
  exact tag/SHA after reading the record. Public publish is the final
  one-way door.

## Stage 7 — Retro & self-update

After every shipped milestone (and after any pipeline failure — including
"the pipeline was too heavy for the job"):

1. Harvest `docs/pipeline/NOTES.md` (every entry since the last milestone is
   consumed or explicitly skipped — then stamp the harvest line) and archive
   BOARD.md's Done column, then fill `docs/templates/retro.md`: what broke,
   which gate should have caught it, model scorecard, checklist gaps,
   proportionality complaints (#friction/#vent entries are evidence here).
2. Fire `packets/terra-boilerplate-update.md` at Terra → diffs against the
   **kit repo**. Apply, log in kit `CHANGELOG.md`, commit.
3. Routing/gate changes need Fable + Ben, never Terra alone.
4. Projects consume an **immutable snapshot** of the kit artifacts they
   bootstrapped from (`docs/pipeline/kit-snapshot/<sha>/`); a mutable local
   path is never gate evidence. An upgrade creates a new snapshot and a
   logged migration in KIT.md. Bootstrap refuses dirty or unidentified kit
   state unless it records a complete content-manifest digest.
5. Recurrence ladder (absorbed from the Hermes autonomic charter): first
   occurrence of a failure — fix it; second — five-whys the mechanism;
   third — automate a guard so it cannot recur silently.

- **Artifact:** completed retro + NOTES harvest marker + archived BOARD
  Done rows + kit CHANGELOG diff or explicit evidence-backed "no kit
  change."
- **Gate:** every NOTES entry since the prior marker consumed or explicitly
  skipped; every Done row archived; routing/gate changes carry Fable + Ben
  approval; resulting kit revision and the project's adoption decision are
  recorded.

## Skills

Models working a stage should use the harness skills that exist for it
instead of freehanding — see `docs/SKILLS.md` for the per-stage map
(brainstorming, TDD, systematic debugging, frontend design, verification,
code review, worktrees, parallel dispatch).

## Debugging protocol (any stage)

1. **Reproduce before you theorize.** No repro, no fix.
2. **Localize by layer** using the project's bug-routing table; a bug that
   fits no row gets its row added first.
3. **Mechanism before fix.** Bad state had a writer. Find the writer.
4. **Hypotheses must predict.** "If it's X, the log shows Y at T." Go look.
5. Fix ships with a regression test and, where the layer was
   under-observed, the instrumentation that would have caught it in minutes.
   (Skill: `superpowers:systematic-debugging`.)

## Definition of done (universal)

- [ ] Acceptance criteria met, each with evidence per the contract above
- [ ] Tests written, run, passing; anti-gaming mutation verified to fail them
- [ ] Reviewed by models that didn't write it (both gates)
- [ ] Observability decision made: failure signal named + tested, or N/A
      with reviewer-accepted rationale
- [ ] Docs updated **iff** behavior, interfaces, operations, or durable
      ground truth changed
- [ ] STATE.md note written so the next session resumes in one read
