# Code review checklist

Reviewer is never the author (`ROLES.md`). Findings are fixed or waived in
writing — never silently dismissed.

## Correctness
- [ ] Does what the packet's acceptance criteria say — verified against them line by line
- [ ] Edge cases: zero, boundary, stale/late input, disconnect/reconnect, permission denied, double delivery
- [ ] Error paths handled per DESIGN.md degradation table (fail-closed where specified)
- [ ] No silent catch-and-continue; failures are observable

## API & platform (Apple projects)
- [ ] Swift concurrency: no racey `@Published` writes off-main, `@MainActor` where UI-bound, no unstructured `Task {}` leaks
- [ ] Lifecycle: watchOS/iOS background transitions, scene phases, session invalidation handled
- [ ] CoreMotion: timestamps used (not arrival time), reference frames explicit, rates respected
- [ ] CGEvent/Accessibility: permission checked before injection, denial surfaced to the user, no retry storm
- [ ] Display coordinates: multi-display and origin conventions correct; bounds clamped

## Scope & fit
- [ ] Patch is minimal — no drive-by rewrites, no out-of-scope files touched
- [ ] Matches surrounding idiom (naming, error style, comment density)
- [ ] No new dependency without an ADR
- [ ] Respects module boundaries from DESIGN.md (Fable's integration pass confirms)

## Tests & instrumentation
- [ ] Tests from the test spec exist and were RUN (evidence attached)
- [ ] Anti-gaming: deleting the feature fails the tests
- [ ] New path is instrumented; a failure here would be visible in logs
- [ ] No test asserts an implementation echo instead of behavior

## Security
- [ ] No secrets/keys/tokens in the diff
- [ ] Input from network/IPC validated at the boundary
- [ ] Injection surfaces (shell, SQL, eval, CGEvent from remote input) bounded

## Self-report quality
- [ ] Author stated confidence + assumptions; assumptions verified or escalated
