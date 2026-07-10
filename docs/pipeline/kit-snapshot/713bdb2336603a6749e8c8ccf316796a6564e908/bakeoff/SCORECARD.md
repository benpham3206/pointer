# Bake-off scorecard

Score each task response 0–2 per criterion (0 = fails, 1 = adequate,
2 = strong). Compilation is a gate: if it doesn't build, the task caps at
the Compiles row (everything else scores 0).

| Criterion | What to check | Weight |
|---|---|---|
| Compiles | Actually builds in Xcode / `swiftc`. Not "should compile." | ×2 |
| Apple API correctness | CoreMotion (timestamps, reference frames), Swift concurrency (`@MainActor`, actor isolation, task lifetimes), AppKit/`CGEvent`, permission flows | ×2 |
| Bug awareness | Handles stale packets, timestamps vs arrival time, reconnects, display bounds, nil/denied states — unprompted | ×2 |
| Minimality | Patches the ask; no rewrite, no invented abstractions | ×1 |
| Architecture fit | Respects the existing module layout and idiom of the provided files | ×1 |
| Testability | Adds tests/logs/instrumentation instead of guessing | ×1 |
| Explanation quality | Reviewable reasoning; assumptions stated; no confident hand-waving | ×1 |

**Task score** = Σ(score × weight), max 20.

**Task 05 (review-only) exception:** nothing compiles in a review task.
Its "Compiles" row is replaced by **Claim accuracy** (×2): each finding
checked against the file — 2 = all CONFIDENT claims verified true, 1 = minor
misses, 0 = any confident claim false. Weights otherwise unchanged.

## Score sheets (one per task per blinded result — copy this block)

Task: __ · Blinded ID: __ (A/B/C per `results/KEY.md`, key withheld until
all sheets complete) · Build log: `results/<task>-<ID>-build.log`

| Criterion | Score 0–2 | Scorer (identity) | Note |
|---|---|---|---|
| Compiles (05: Claim accuracy) | | | |
| Apple API correctness | | | |
| Bug awareness | | | |
| Minimality | | | |
| Architecture fit | | | |
| Testability | | | |
| Explanation quality | | | |

## Results (filled only after all sheets are complete and the key is opened)

| Task | A | B | C | Task winner |
|---|---|---|---|---|
| 01 CoreMotion sampling | | | | |
| 02 Cursor injection | | | | |
| 03 Filter pipeline | | | | |
| 04 Display mapping | | | | |
| 05 Bug review | | | | |
| **Weighted total** | | | | |

Decision rule: weighted total → task wins → Ben (dated).
Implementation owner: ______ · Primary reviewer: ______ · Date: ______
· Ben's signature line: ______ → recorded in `ROLES.md`.
