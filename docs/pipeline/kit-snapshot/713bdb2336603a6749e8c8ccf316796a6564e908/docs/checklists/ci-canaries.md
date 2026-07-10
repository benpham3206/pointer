# CI negative canaries — Stage 2 fixture procedure

CI that has only ever been green is unproven: a green run cannot show the
gate *fails* when it should. Before the first task packet, run these five
fixtures against the installed workflow on a scratch branch, record each
run URL + non-zero conclusion in `docs/pipeline/evidence/ci-canaries.md`,
then delete the branch. Re-run after any workflow change.

| # | Canary | Fixture (commit to scratch branch, push, observe CI) | Required result |
|---|---|---|---|
| 1 | Type error | Swift: `let x: Int = "s"` in any target file · TS: same in a .ts file · Python: introduce an obvious mypy error | workflow FAILS |
| 2 | Failing test | Add a test asserting `1 == 2` | workflow FAILS |
| 3 | Zero collected tests | Empty/rename the test dir (Swift: point TEST_SCHEME at a target with no tests) | workflow FAILS — pytest exits 5→fail; jest/vitest fail by default (never enable `--passWithNoTests`); Swift template asserts `Executed [1-9]` |
| 4 | Missing formatter/linter | Remove the lint tool from deps (or rename its config so invocation errors) | workflow FAILS, not skips |
| 5 | Unresolved placeholder | Restore any `SETME` value or a `PIN to SHA` comment | workflow FAILS at the refuse-placeholders step |

Then one clean green run **on the same workflow revision** as the canaries.

Evidence record format (one line per canary):
`| <#> | <fixture commit sha> | <CI run URL> | FAIL as required |`

A skipped required job anywhere in these runs is `NOT_RUN`, never `PASS`.
