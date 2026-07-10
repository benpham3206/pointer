# Swift bake-off — who writes the code

Roles are assigned by measured performance on YOUR codebase, not model
status. Five tasks, same prompt and same files to every contestant
(Fable 5, GPT-5.6 Sol, Grok 4.5), scored on `SCORECARD.md`.

The tasks are grounded in **pointer** (`~/Projects/pointer`) — the first
dogfood project — but the format is reusable: for a new stack, rewrite the
five tasks in that stack's terms and keep the scorecard.

## Protocol

1. For each task in `tasks/`, paste the task file + the exact files it
   lists to each model. Fresh session per model per task — no
   cross-contamination, no retries.
2. Save each response verbatim under a **blinded ID**:
   `results/<task>-A.md`, `-B.md`, `-C.md`; the ID→model key lives in
   `results/KEY.md` and is withheld from scorers until scoring is done.
3. Compile check is mechanical and mandatory: paste each response into a
   scratch target, run `xcodebuild`/`swiftc`, save the build log next to the
   result. "Looks compilable" scores 0.
4. Scoring: **no contestant scores its own output** — every scorecard row
   records the scorer's identity. Ben scores the mechanical rows
   (compiles, minimality); a non-contestant session (or Ben) scores the
   rubric rows against `SCORECARD.md`.

## Outcome (decision rule, in order)

1. Highest **weighted total** across the five tasks → implementation owner.
2. Tie-break 1: most individual task wins.
3. Tie-break 2: Ben decides, dated, on the scorecard.
4. Runner-up → primary correctness reviewer.

No stack routing exists until the scorecard is complete and signed
(scorer identities + build logs + Ben's date). Until then `ROLES.md` says
`pending`, and packets assign reviewers per its assignment invariant.

## Re-run triggers

- Any contestant ships a major version.
- Two consecutive milestones where the implementer's patches needed rework
  (per retro scorecards).
- New stack (the Swift result doesn't transfer to, say, a TypeScript web app
  — run a mini bake-off of 2–3 tasks in the new stack).
