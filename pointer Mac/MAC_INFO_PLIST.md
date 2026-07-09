# macOS target setup — Info.plist & entitlements

## Xcode target (manual)

1. Open `pointer.xcodeproj` in Xcode.
2. **File → New → Target… → macOS → App**
3. Product name: **pointer Mac** (or `pointer Mac`), Interface **SwiftUI**, Language **Swift**.
4. Set **Bundle Identifier** to `bp.pointer.macos` (recommended) or `bp.pointer`.
5. Delete boilerplate `ContentView` / `*App.swift` if they duplicate `pointer Mac/` sources.
6. In the Project navigator, add folder membership for:
   - `pointer Mac/` (all `.swift` files)
   - `Shared/` (`MouseController.swift`)
7. **Build Settings → Code Signing Entitlements**: `pointer Mac/pointerMac.entitlements`
8. Scheme: run **pointer Mac** on **My Mac**.

`MACOS_TARGET_ANALYSIS.md` in the repo root has full pbxproj notes; prefer the Xcode UI over hand-editing `project.pbxproj`.

## Generated Info.plist additions

When `GENERATE_INFOPLIST_FILE = YES`, merge these via **Build Settings → Info.plist Values** (`INFOPLIST_KEY_*`) or an **Info.plist** file referenced by `INFOPLIST_FILE`.

| Key | Type | Value |
|-----|------|--------|
| `NSLocalNetworkUsageDescription` | String | Pointer listens on your local network so your iPhone can forward Apple Watch motion to control the Mac cursor. |
| `NSBonjourServices` | Array | `_pointer._tcp` |
| `CFBundleDisplayName` | String | Pointer |
| `LSMinimumSystemVersion` | String | `14.0` (or your `MACOSX_DEPLOYMENT_TARGET`) |

### Example `Info.plist` fragment (if not using generated keys only)

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Pointer listens on your local network so your iPhone can forward Apple Watch motion to control the Mac cursor.</string>
<key>NSBonjourServices</key>
<array>
    <string>_pointer._tcp</string>
</array>
```

## Privacy & permissions (runtime, not Info.plist)

| Capability | Notes |
|------------|--------|
| **Accessibility** | Required for `CGWarpMouseCursorPosition`. User grants in **System Settings → Privacy & Security → Accessibility**. `CursorAccessibility.requestTrustPrompt()` triggers the standard prompt. |
| **Local network** | macOS 14+ may show a local-network consent dialog when `NWListener` advertises Bonjour; `NSLocalNetworkUsageDescription` supplies the string. |

## Entitlements

File: `pointer Mac/pointerMac.entitlements`

- `com.apple.security.app-sandbox` = **false** — sandbox blocks reliable cursor warping without extra entitlements; this companion is a dev-style menu-bar/window utility.
- `com.apple.security.network.server` / `client` = **true** — documents TCP listener + outbound use if needed.

If you later enable App Sandbox, you must keep network server/client entitlements and accept that cursor control may require additional review and user Accessibility trust anyway.

## Bonjour service (must match iPhone forwarder)

| Field | Value |
|-------|--------|
| Type | `_pointer._tcp` |
| Domain | `local.` |
| Name | `pointer` (service instance; companion iOS bundle is `bp.pointer`) |

Motion payload: JSON object per line (or single JSON object), same keys as the Watch `MotionManager` dictionary: `roll`, `pitch`, `yaw`, `ax`, `ay`, `az`, `gx`, `gy`, `gz`. `MouseController` uses `roll` and `pitch`.