# LESSONS.md — pointer (append-only agent ledger)

Per `~/Projects/pipeline/WORKTREE_PROTOCOL.md`: every agent working this repo
reads this file at spawn and appends `{component, lesson, evidence}` at hand-off.

- {component: codex-sandbox, lesson: "Nested Grok-inside-Codex always fails — Grok's CLI needs machine-local session state the workspace-write sandbox forbids; coordinator must spawn Grok at its own level", evidence: "FS_PERMISSION_DENIED, Sol-P1 2026-07-14"}
- {component: codex-sandbox, lesson: "Codex workers cannot run xcodebuild (CoreSimulator/XPC + /tmp cache denied); DoD must use `xcrun swiftc -typecheck` and the coordinator runs the real build at the gate", evidence: "exit 143 in Sol-P1; sandbox-flag workarounds in later lanes"}
- {component: grok-bridge, lesson: "Grok runs can 'complete' having written NOTHING (narration-only, no edits, no report) — every Grok gate must verify file mtime + a content grep before trusting the run status", evidence: "run-mrlmiy30 + resume run-mrlmmgt1, PhonePointerEngine untouched twice, 2026-07-14"}
- {component: chain-of-command, lesson: "Three failed worker attempts on one packet = coordinator takes the task; retrying a silently-failing runtime a 4th time is thrashing", evidence: "phone sign-chain fix applied by FABLE after 3 Grok failures"}
- {component: ray-model, lesson: "Track the POINTING RAY (world-frame direction of a body axis), never body attitude — attitude conflates wrist/grip rotation with pointing; azimuth must increase screen-right: atan2(worldX, worldY) for +Y ray under .xArbitraryZVertical", evidence: "phone inversion + dead angular height + wrist-rotation artifacts, derivation in PhonePointerEngine.swift comments"}
- {component: xcode-project, lesson: "Synchronized folder groups compile EVERYTHING in the folder — Xcode template boilerplate left after target creation causes duplicate @main; typecheck-all-files misses target-level errors the real xcodebuild catches", evidence: "Pointer_MacApp.swift collision at P1 gate"}
- {component: deployment, lesson: "'It doesn't work' on this project is stale-install or server-not-running until proven otherwise; verify installed-binary strings/mtime before debugging code", evidence: "recurring across sessions 2026-07-08→14"}
