# iOS Local Network + Bonjour (MacForwarder)

Manual Xcode setup for the **pointer** iOS target (`bp.pointer`). Do **not** hand-edit `project.pbxproj`.

## Why these keys exist

`MacForwarder` (`pointer/MacForwarder.swift`) browses the local network with `NWBrowser` for Bonjour type **`_pointer._tcp`** (same constant as `MacMotionReceiver` on macOS). On iOS 14+, that requires:

1. **`NSLocalNetworkUsageDescription`** — text for the Local Network privacy prompt.
2. **`NSBonjourServices`** — array listing every Bonjour type the app **browses** (not advertises).

Without both, browsing often fails silently or the system denies access.

The iOS target already has **`GENERATE_INFOPLIST_FILE = YES`** (no checked-in `Info.plist`). Add keys through Xcode’s **Info** UI and/or **Build Settings → Info.plist Values** (`INFOPLIST_KEY_*`).

---

## Step-by-step in Xcode

1. Open **`pointer.xcodeproj`** in Xcode.
2. In the project navigator, select the **pointer** project (blue icon), then the **pointer** target under **TARGETS** — **not** “pointer Watch App”.
3. Confirm **Build Settings** (All + Combined): **Generate Info.plist File** (`GENERATE_INFOPLIST_FILE`) = **Yes**.

### A. Info tab (recommended — handles `NSBonjourServices` array)

4. Open the **Info** tab for the **pointer** target.
5. Under **Custom iOS Target Properties**, click **+** and add:

| Key | Type | Value |
|-----|------|--------|
| **Privacy - Local Network Usage Description** (`NSLocalNetworkUsageDescription`) | String | `Pointer finds your Mac on the local network to forward Apple Watch motion.` |
| **Bonjour services** (`NSBonjourServices`) | Array | *(one item below)* |

6. Expand **Bonjour services** → **Item 0** → set type **String**, value:

```text
_pointer._tcp
```

7. **Product → Clean Build Folder**, then build/run **pointer** on a physical iPhone (simulator does not fully exercise Local Network prompts).

### B. Build Settings → Info.plist Values (string key + optional duplicate path)

Same target → **Build Settings** → filter **Info.plist** → section **Info.plist Values**.

Add or set:

| Build setting name | Plist key | Value (copy-paste) |
|--------------------|-----------|-------------------|
| `INFOPLIST_KEY_NSLocalNetworkUsageDescription` | `NSLocalNetworkUsageDescription` | `Pointer finds your Mac on the local network to forward Apple Watch motion.` |

Apple maps each plist key to `INFOPLIST_KEY_<KeyName>` ([Managing your app’s information property list values](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list)). The usage string is a plain **String** build setting.

**`NSBonjourServices` (array):** Prefer the **Info** tab (steps 5–6). If you only set build settings, Xcode may not expose a one-line `INFOPLIST_KEY_NSBonjourServices` for a string array in all versions — use the merge file in section C if the Info tab is unavailable.

---

## Option C — small merge plist (still no `pbxproj` hand-edits)

If you need a file on disk instead of only the Info tab:

1. **File → New → File → Property List** → name e.g. `pointer-iOS-InfoAdditions.plist` under `pointer/` or `docs/` (your choice).
2. In the new plist, add:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Pointer finds your Mac on the local network to forward Apple Watch motion.</string>
	<key>NSBonjourServices</key>
	<array>
		<string>_pointer._tcp</string>
	</array>
</dict>
</plist>
```

3. Select the **pointer** target → **Build Settings** → set **Info.plist File** (`INFOPLIST_FILE`) to that path (e.g. `pointer/pointer-iOS-InfoAdditions.plist`).
4. Leave **`GENERATE_INFOPLIST_FILE = Yes`**. Xcode **merges** this file with generated keys from **Info.plist Values** at build time.

Do **not** add the merge plist to **Copy Bundle Resources**.

---

## Exact keys and values (summary)

| Info.plist key | Type | Exact value |
|----------------|------|-------------|
| `NSLocalNetworkUsageDescription` | String | `Pointer finds your Mac on the local network to forward Apple Watch motion.` |
| `NSBonjourServices` | Array of String | Single element: `_pointer._tcp` |

**Must match code:** `MacForwarder.bonjourType` / `NWBrowser(for: .bonjour(type: "_pointer._tcp", domain: nil), …)`.

**Must match Mac listener:** macOS advertises the same type (see `BUILD.md` and `pointer Mac/MAC_INFO_PLIST.md` for the Mac target).

---

## Verify after build

1. Install on a **physical iPhone** on the same Wi‑Fi as the Mac.
2. Launch **Pointer Mac** first (listener active).
3. Launch **pointer** on iPhone — first browse should trigger **Local Network** permission (wording from `NSLocalNetworkUsageDescription`).
4. In Xcode: **pointer** target → **Info** tab should still show both keys; or inspect the built app:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'pointer.app' -path '*Debug-iphoneos*' 2>/dev/null | head -1)
/usr/libexec/PlistBuddy -c 'Print :NSLocalNetworkUsageDescription' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :NSBonjourServices' "$APP/Info.plist"
```

Expected: your usage string and `Array { _pointer._tcp }`.

---

## Runtime checklist

| Step | Action |
|------|--------|
| iPhone | Allow **Local Network** when prompted (Settings → Privacy & Security → Local Network → **pointer** = On if dismissed). |
| Mac | Pointer Mac running; Bonjour listener advertising `_pointer._tcp`. |
| Network | Same LAN; avoid VPNs that block mDNS if browse fails. |

`MacForwarder` also sets `NWParameters.tcp.includePeerToPeer = true` for peer discovery; the Bonjour type in plist remains **`_pointer._tcp`**.

---

## What not to change here

- **pointer Watch App** target — does not run `MacForwarder`; no need for these keys on Watch unless you add network browse there later.
- **`project.pbxproj`** — use Xcode UI only; repo may already list `INFOPLIST_KEY_CFBundleDisplayName` etc. without Local Network keys until you add them.

---

## Related docs

- `BUILD.md` — § Info.plist / entitlements (iOS + Mac table).
- `pointer Mac/MAC_INFO_PLIST.md` — macOS listener keys (mirror Bonjour type).