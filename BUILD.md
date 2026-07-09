# Pointer — build & run (v1 relay)

## Reconstructed batch `deleg_dbe1b738` (2026-07-08)

Three parallel workers wrote the implementation; the async completion message was lost to context compaction. Deliverables on disk:

| Stream | Files |
|--------|--------|
| **Shared** | `Shared/MotionPayload.swift`, `Shared/MouseController.swift` (CGEventPost on macOS) |
| **iOS relay** | `pointer/PhoneWatchReceiver.swift`, `PhoneRelayState.swift`, `MacForwarder.swift`, `ContentView.swift` |
| **Mac receiver** | `pointer/MacMotionReceiver.swift`, `MacContentView.swift`, `CursorAccessibility.swift` (merged from `pointer Mac/`) |

**Single-folder layout:** macOS and iOS both compile from `pointer/` + `Shared/`.

`pointer/MotionPayload.swift` and `pointer/MouseController.swift` are **symlinks** to `../Shared/` so the iOS synchronized root group picks up shared types (Xcode does not compile sources inside a symlinked `Shared/` directory reliably).

## Data path

```
Watch (MotionManager, WCSession)
  → iPhone (PhoneWatchReceiver)
  → MacForwarder (Bonjour `_pointer._tcp`, newline-delimited JSON)
  → Mac (MacMotionReceiver → MouseController → CGEventPost)
```

## Xcode setup

### 1. iOS + Watch (existing)

Targets **pointer** and **pointer Watch App** already use synchronized `pointer/` and `pointer Watch App/`. Ensure **Compile Sources** includes everything under `pointer/` except nothing extra — duplicate `MotionPayload.swift` in `pointer/` was removed; use `Shared/` only.

### 2. Add macOS target (one-time)

1. **File → New → Target → macOS → App**
2. Product name: **Pointer Mac** (or reuse name **pointer** for the Mac product)
3. Bundle ID: **`bp.pointer.macos`** (recommended)
4. **Delete** Xcode boilerplate `*App.swift` / `ContentView` from the new target group.
5. In **Build Phases → Compile Sources** for the **macOS** target, include the same synchronized **`pointer/`** root as iOS **or** add target membership on the `pointer` folder for both iOS and macOS (Project → `pointer` folder → Target Membership: check **pointer** + **Pointer Mac**).
6. Confirm **`Shared/MotionPayload.swift`** and **`Shared/MouseController.swift`** compile on Mac (via symlink `pointer/Shared` or separate `Shared` group on both targets).
7. **Do not** add `pointer Mac/pointerMacApp.swift` to any target (second `@main`). Legacy folder is deprecated.

### 3. Info.plist / entitlements

**macOS target** — add (Build Settings → Info.plist Values or `Info.plist`):

| Key | Value |
|-----|--------|
| `NSLocalNetworkUsageDescription` | Pointer listens on your local network so your iPhone can forward Apple Watch motion. |
| `NSBonjourServices` | `_pointer._tcp` |

Entitlements template: `pointer Mac/pointerMac.entitlements` (copy path into **Code Signing Entitlements** for the Mac target).

**iOS target** — for Bonjour **browse** from `MacForwarder`, add:

| Key | Value |
|-----|--------|
| `NSLocalNetworkUsageDescription` | Pointer finds your Mac on the local network to forward watch motion. |
| `NSBonjourServices` | `_pointer._tcp` |

See `pointer Mac/MAC_INFO_PLIST.md` for detail.

### 4. Runtime permissions

- **Mac:** System Settings → Privacy & Security → **Accessibility** (required for cursor move).
- **iPhone:** Local Network prompt when browsing for Mac.

## Run order

1. Launch **Mac** app → listener advertising `pointer._pointer._tcp`.
2. Launch **iPhone** app → should browse and connect to Mac.
3. On **Watch**, start tracking → cursor should move on Mac.

## Build (CLI)

```bash
cd /Users/benjaminpham/Projects/pointer
xcodebuild -scheme pointer -destination 'generic/platform=iOS' -quiet build
# After macOS target exists:
xcodebuild -scheme 'pointer Mac' -destination 'platform=macOS' -quiet build
```

## Gaps / v2

- BLE Watch→Mac direct (Mac peripheral) — not in v1.
- `pointer Mac/` duplicate sources — superseded by `pointer/`; safe to delete after Mac target uses `pointer/` only.
- Hand-editing `project.pbxproj` for macOS target — prefer Xcode UI (`MACOS_TARGET_ANALYSIS.md`).