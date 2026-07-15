# DESIGN.md — pointer feel & interface principles

Distilled 2026-07-11 from Ben's Apple-craft notes. These are the
principles the app is judged against, not a spec.

## SwiftUI is the play

Native animations, haptics, and layout scaling come free — never write
constraint code the framework already solves. One SwiftUI codebase
philosophy across Watch, iOS, and Mac targets.

## HIG, kept modern

- **System materials used functionally, never decoratively.** Vibrancy
  and translucency earn their place when they communicate depth or
  context bleed-through; custom blur soup does not.
- Strict grid alignment. SF Symbols only. Padding is a feature —
  breathing room reads as confidence.

## Micro-interactions ARE the product

For a Watch→Mac cursor app, feel is not polish on top of the product —
it *is* the product:

- **Haptic confirmation on every registered action** (click lands, mode
  switch, connection state). Precise ticks, not generic buzzes.
- **Fluid transition states** — cursor engage/disengage, reconnect —
  animated so state change explains itself. No hard cuts between
  connection states.
- **Latency honesty**: show real connection state, never an optimistic
  spinner. A cursor that lies about being connected is broken even
  when it works.

This is the line between a cheeks app and a premium one.

## Boilerplate rule

After v1 ships: extract the UDP session + discovery + SwiftUI shell
into a template (held-style), so the next Watch/iPhone→Mac tool skips
the config phase and goes straight to raw logic.
