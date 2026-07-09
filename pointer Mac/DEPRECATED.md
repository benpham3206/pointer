# Deprecated

Mac sources were **merged into** `../pointer/` behind `#if os(macOS)`:

- `MacMotionReceiver.swift`
- `MacContentView.swift`
- `CursorAccessibility.swift`

Use **`pointer/pointerApp.swift`** as the single `@main` for the macOS target (same `pointer/` folder as iOS).

Keep **`pointerMac.entitlements`** and **`MAC_INFO_PLIST.md`** as reference when configuring the macOS target in Xcode.

Do **not** compile `pointerMacApp.swift` alongside `pointer/pointerApp.swift`.