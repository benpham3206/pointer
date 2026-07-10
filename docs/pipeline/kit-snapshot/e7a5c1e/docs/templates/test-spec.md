# Test spec — <packet ID / feature>

Author: Sol · Status: draft / agreed

## What this layer can prove
And what it can't — name the gap and where it's covered instead
(integration, manual matrix, instrumentation-in-prod).

## Cases
| # | Case | Setup | Action | Expected | Kind (unit/int/e2e/manual) |
|---|---|---|---|---|---|

Must include, where applicable: the zero case, the boundary, **malformed
input**, the stale/late/**reordered** input, the disconnect/reconnect, the
permission-denied **and permission-revoked-at-runtime**, the
double-delivery.

## Failure assertions (mandatory for every forced-failure case)
Each forced failure asserts the structured error payload — at minimum
`component`, `failure_type`, `root_cause` — and asserts that secrets and
raw sensitive payloads are **absent** from the error and its logs. A test
spec whose failure cases don't assert these fields is invalid, regardless
of coverage breadth.

## Anti-gaming clause
Tests assert behavior, not implementation echoes. A test that would still
pass if the feature were deleted is not a test. Reviewer checks that failing
the feature fails the test.

## Manual acceptance matrix (hardware / human-facing only)
| Scenario | Device/config | Steps | Pass looks like |
|---|---|---|---|
