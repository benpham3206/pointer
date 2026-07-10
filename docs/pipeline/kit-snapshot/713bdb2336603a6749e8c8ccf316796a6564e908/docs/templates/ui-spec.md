# UI spec — <project>

Stage 2 artifact for anything user-facing. UI acceptance criteria come from
this file; "looks good" is not a criterion. Skills:
`frontend-design` / `design-taste-frontend` (direction + anti-slop),
`dataviz` (any chart), `paper-desktop:design-to-code` (when a Paper design
exists), `paper-desktop:code-to-design` (extract tokens from existing code).

## Visual identity

**Register first** (absorbed from Impeccable/TASTE): is this a **brand**
surface (expressive, personality allowed) or a **product** surface (recedes
behind the user's task)? Then one concrete sentence of the physical scene —
who is using it, where, on what, in what mood — before any theme talk. House
rule: *industrial clarity maintained, not themed slop* — clarity is the
default theme; decoration must argue for itself.

If the identity is vague (the normal case): Fable produces **3 direction
cards**, Ben picks one — that's the [BEN] taste gate; record the pick + date.

| Card | References (apps/sites/eras) | Type | Color | Density/motion | One line of intent |
|---|---|---|---|---|---|
| A | | | | | |
| B | | | | | |
| C | | | | | |

**Chosen:** ___ (Ben, date) · deviations from the card require a new pick.

## Design tokens (once a direction is chosen)
Type scale, spacing unit, radius, color roles (bg/surface/text/accent/
danger), dark-mode behavior, platform idiom notes (SwiftUI materials, web
CSS vars, …). Tokens live in code from the first screen — one source.

## Screen inventory
| Screen/view | Purpose | States (empty · loading · error · full) | Platform notes |
|---|---|---|---|
Every screen ships all four states; an unstyled error state fails review.

## Interaction map
Primary flows step-by-step (≤ 7 steps each), including the failure branches.
Where latency is perceptible, name the feedback (skeleton, progress,
optimistic update + rollback).

## UI acceptance criteria (feed Stage 3 packets)
- [ ] Matches chosen direction card (reviewer eyeballs against references)
- [ ] All inventory states implemented; forced-error screenshot attached
- [ ] Keyboard/VoiceOver or platform-equivalent accessibility pass
- [ ] Dark and light mode (or documented single-theme decision)
- [ ] No layout traps: longest realistic string, smallest supported window
