# Grok 4.5 implementation packet: Watch to Mac keyboard send path

## Objective

Complete the backend path used by the Watch UI so literal text and special-key taps travel directly over the BLE control characteristic when BLE owns the connection, or fall back through `WCSession` to the iPhone and then to `MacForwarder`.

This is a bounded coding packet. You are the only writer in this worktree while executing it. Do not delegate further.

## Ownership

You may modify exactly these two files:

- `pointer Watch App/MotionManager.swift`
- `pointer/PhoneWatchReceiver.swift`

Do not create, modify, format, or delete any other file. Do not commit, merge, push, publish, or rewrite history.

## Required function signatures

Preserve these Watch-facing declarations exactly (including the existing default, which is required by the current one-argument Watch UI call):

```swift
func sendText(_ text: String)
func sendKey(keycode: Int, modifiers: Int = 0)
```

The phone relay change belongs inside the existing function:

```swift
private func handleIncoming(_ message: [String: Any])
```

Call the existing `MacForwarder` APIs with their exact signatures; do not alter or duplicate them:

```swift
func sendText(_ text: String)
func sendKey(keycode: Int, modifiers: Int, action: Int)
```

## Current protocol evidence; preserve it

- `MotionManager.sendControl(_:)` already attempts `BLETransport.frame(for:)` plus `bleTransport.sendControl(_:)` first and calls `sendControlToPhone(_:)` only when BLE does not own the frame. Reuse this routing; do not introduce another transport abstraction.
- `BLETransport.frame(for:)` already encodes a text dictionary as frame type `0x06`, one unsigned byte of UTF-8 length, then the UTF-8 bytes. It encodes a key dictionary as frame type `0x07`, a little-endian `UInt16` keycode, one modifiers byte, and one action byte.
- `MacForwarder.sendText(_:)` already chunks and encodes text into `0x06` frames. `MacForwarder.sendKey(keycode:modifiers:action:)` already encodes `0x07`. The worker must route to these methods; `MacForwarder.swift` is read-only for this packet.
- `PhoneWatchReceiver.handleIncoming(_:)` currently sends all non-wake messages through `macForwarder.forwardMotion(message)`. That generic path must remain the default for motion and existing controls, but text and key require dedicated dispatch so valid keyboard messages are not silently dropped or double-forwarded.

## Required dictionary shapes

Construct and preserve these exact payload fields and values:

```swift
["type": "text", "text": textChunk]
["type": "key", "keycode": keycode, "modifiers": modifiers, "action": 2]
```

Equivalent abstract shapes are `{type:'text', text:...}` and `{type:'key', keycode:..., modifiers:..., action:2}`. Do not add timestamps or unrelated fields to these keyboard dictionaries.

## Implementation constraints

### Watch: `MotionManager.swift`

1. `sendText(_:)` remains a no-op for an empty string.
2. Split non-empty text into ordered chunks whose `utf8.count` is at most 255 bytes **before** calling `sendControl(_:)`. Every emitted chunk must be valid Swift `String`/UTF-8; never split inside a Unicode scalar. Preserve all input scalars in order. A chunk of exactly 255 bytes is valid.
3. Call `sendControl(["type": "text", "text": textChunk])` once per chunk. Because chunking precedes routing, each chunk independently uses BLE when connected and otherwise uses the existing WCSession fallback.
4. `sendKey(keycode:modifiers:)` emits exactly one key dictionary with `action: 2` through the existing `sendControl(_:)` helper.
5. Do not change BLE connection policy, retry/backpressure behavior, WCSession exactly-once fallback behavior, motion streaming, calibration, click delivery, or Watch UI.

### Phone: `PhoneWatchReceiver.swift`

1. In `handleIncoming(_:)`, dispatch a valid `type == "text"` message to `macForwarder.sendText(_:)`.
2. Dispatch a valid `type == "key"` message to `macForwarder.sendKey(keycode:modifiers:action:)`. Require numeric `keycode` and `modifiers`, and require `action == 2`; pass `2` as the action.
3. Text/key messages handled by those dedicated methods must not also pass through `macForwarder.forwardMotion(_:)`. Each incoming keyboard dictionary gets one Mac forwarding path only.
4. Preserve the existing `wake` exclusion, phone-pointer suppression for motion/calibration, relay-state accounting, connection setup, background task behavior, and `sensorDebugStreamer` behavior.
5. Do not silently discard malformed text/key dictionaries. Record an explicit structured relay failure through `relayState.applyFailure(component:rootCause:failureType:)` with component `PhoneWatchReceiver.handleIncoming`, a concrete root cause identifying the missing/invalid field, and failure type `.invalidPayload`. Keep UI-published relay state mutation on the main queue, consistent with the surrounding code.

## Non-goals

- No Watch UI or coordinator work, including `WatchKeyboardView.swift`.
- No edits to `BLETransport.swift`, `MacForwarder.swift`, project settings, schemes, tests, docs, assets, or generated/user Xcode state.
- No new transport, protocol version, acknowledgement layer, retry policy, telemetry system, or keyboard layout behavior.
- No architecture or security-boundary decisions. Surface a conflict instead of broadening scope.

## Acceptance checks

- The only source paths changed are the two owned files.
- Watch text of 1, 255, 256, and multi-byte UTF-8 inputs is emitted in order, with every text dictionary containing valid text and no more than 255 UTF-8 bytes.
- BLE-connected keyboard traffic goes through `BLETransport.frame(for:)`/the BLE control characteristic; BLE-unavailable traffic uses the existing `sendControlToPhone(_:)` WCSession path.
- The phone calls the dedicated Mac forwarder method for valid text and key messages and does not additionally call `forwardMotion(_:)` for the same keyboard message.
- Key dictionaries always contain `type == "key"`, the supplied keycode and modifiers, and `action == 2`.
- Malformed keyboard payloads produce a structured `.invalidPayload` failure rather than a crash, bare log, or silent return.
- Existing motion, calibration, click, wake, debug-stream, and relay status paths remain behaviorally unchanged.

## Verification commands

Run from the repository root. These focused one-liners avoid SwiftUI preview macros and use a writable module cache.

Watch typecheck:

```bash
mkdir -p /tmp/pointer-swift-module-cache && CLANG_MODULE_CACHE_PATH=/tmp/pointer-swift-module-cache SWIFT_MODULE_CACHE_PATH=/tmp/pointer-swift-module-cache xcrun --sdk watchsimulator swiftc -typecheck -sdk "$(xcrun --sdk watchsimulator --show-sdk-path)" -target arm64-apple-watchos26.5-simulator 'pointer Watch App/MotionManager.swift' 'pointer Watch App/BLETransport.swift' 'pointer Watch App/TrackingRuntime.swift' 'pointer Watch App/WorkoutKeepAlive.swift'
```

iOS typecheck:

```bash
mkdir -p /tmp/pointer-swift-module-cache && CLANG_MODULE_CACHE_PATH=/tmp/pointer-swift-module-cache SWIFT_MODULE_CACHE_PATH=/tmp/pointer-swift-module-cache xcrun --sdk iphonesimulator swiftc -typecheck -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios26.5-simulator pointer/PhoneWatchReceiver.swift pointer/PhoneRelayState.swift pointer/MacForwarder.swift pointer/SensorDebugStreamer.swift pointer/MotionPayload.swift
```

Ownership/status evidence:

```bash
git diff -- 'pointer Watch App/MotionManager.swift' pointer/PhoneWatchReceiver.swift
git status --short
```

## DEFINITION OF DONE

Return only after both focused typechecks exit 0 and the diff satisfies every constraint above. Your return must contain:

1. A concise implementation summary.
2. The exact touched-file list.
3. The exact commands run and their exit codes.
4. The final 20 lines of Watch typecheck output and the final 20 lines of iOS typecheck output. If a successful command emits no text, state `(no output; exit 0)` rather than inventing a tail.
5. The complete final `git status --short` output, explicitly distinguishing pre-existing paths from your two owned edits.
6. Any failure or residual risk, in structured form: `{component, root cause, failure type}`.

If either typecheck fails, an out-of-scope file changes, or a requirement conflicts with the current tree, stop and report the evidence. Do not work around the ownership boundary.

Return contract: summary, touched files, checks run, typecheck tails, complete git status, failures, residual risk.
