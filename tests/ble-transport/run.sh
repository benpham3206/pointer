#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/pointer-ble-transport.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
swiftc -emit-library -emit-module -module-name CoreBluetooth \
    "$root/tests/ble-transport/CoreBluetooth.swift" \
    -o "$build/libCoreBluetooth.dylib" \
    -emit-module-path "$build/CoreBluetooth.swiftmodule"
cat "$root/pointer Watch App/BLETransport.swift" \
    "$root/tests/ble-transport/Replay.swift" > "$build/BLETransportReplay.swift"
swiftc -parse-as-library -I "$build" -L "$build" -lCoreBluetooth \
    "$build/BLETransportReplay.swift" -o "$build/replay"
DYLD_LIBRARY_PATH="$build" "$build/replay"
