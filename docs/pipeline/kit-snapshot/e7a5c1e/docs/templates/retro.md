# Retro — <project> · <milestone> · <date>

Feeds the kit self-update loop (PIPELINE.md Stage 7). Honest > flattering:
a falsified attempt with a clean postmortem is a win here.

## What shipped
And the evidence it works (test run, latency number, user action).

## NOTES.md harvest
Entries consumed (link/quote) vs explicitly skipped (why). Stamp NOTES.md
with `--- harvested through <date> ---` when done. #friction/#vent entries
route to "checklist gaps" or "kit diffs" below — that's what they're for.

## What broke, and where the pipeline was standing at the time
| Incident | Stage/gate that should have caught it | Did it? Why not? | Occurrence # (ladder: 1 fix · 2 five-whys · 3 automate a guard) |
|---|---|---|---|

## Model scorecard
| Model | Role this milestone | Over/under-performed routing? | Evidence |
|---|---|---|---|
Two consecutive "under" rows for an implementer ⇒ re-run the bake-off.

## Checklist gaps
Items that should exist in code-review / regression / release / security
checklists and don't. Exact proposed wording.

## Kit diffs proposed
| Kit file | Change | Why |
|---|---|---|
(or: **"No kit changes"** + one sentence why this milestone taught nothing —
that's a legal but suspicious answer.)

## Next milestone's one risk
The single thing most likely to bite next. One sentence.
