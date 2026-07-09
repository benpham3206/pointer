# Shared (pointer)

Swift sources in this folder are intended for **multiple targets** (iOS `pointer`, future macOS target, optionally Watch).

## Xcode target membership (objectVersion 77)

This project uses `PBXFileSystemSynchronizedRootGroup`. New files under `Shared/` are **not** automatically included in every target.

After adding files here:

1. Open `pointer.xcodeproj` in Xcode.
2. For each target that should compile shared code (`pointer`, macOS app when added):
   - Attach `Shared/` via a synchronized root group in **fileSystemSynchronizedGroups**, or
   - Confirm **Compile Sources** lists `MotionPayload.swift` and `MouseController.swift`.
3. **iOS `pointer/` sync group:** hard links at `pointer/MotionPayload.swift` and `pointer/MouseController.swift` point at these files so Xcode compiles them without editing `project.pbxproj`. Re-run after editing Shared sources:
   `ln -f ../Shared/MotionPayload.swift pointer/MotionPayload.swift && ln -f ../Shared/MouseController.swift pointer/MouseController.swift`

Team **9M7LCBZPAV**, bundle IDs **bp.pointer** (iOS) / **bp.pointer.watchkitapp** (Watch).