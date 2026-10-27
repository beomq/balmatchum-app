#!/bin/bash
set -euo pipefail
: "${RUN_TMP:?Set RUN_TMP to a dedicated absolute evidence/cache directory}"
export TMPDIR="$RUN_TMP/"
export CLANG_MODULE_CACHE_PATH="$RUN_TMP/clang"
export SWIFT_MODULECACHE_PATH="$RUN_TMP/swift"
WATCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
APP="$RUN_TMP/WatchPreview.app"
mkdir -p "$APP" "$RUN_TMP/modules"
xcrun --sdk watchsimulator swiftc -parse-as-library -emit-module -emit-library -static \
  -module-name WatchSyncContract -target arm64-apple-watchos10.0-simulator -sdk "$SDK" \
  -emit-module-path "$RUN_TMP/modules/WatchSyncContract.swiftmodule" \
  "$WATCH_DIR"/SyncContract/Sources/WatchSyncContract/*.swift \
  -o "$RUN_TMP/modules/libWatchSyncContract.a"
xcrun --sdk watchsimulator swiftc -parse-as-library \
  -target arm64-apple-watchos10.0-simulator -sdk "$SDK" \
  -I "$RUN_TMP/modules" -L "$RUN_TMP/modules" -lWatchSyncContract \
  "$WATCH_DIR/WatchDashboard.swift" "$WATCH_DIR/PreviewHarness/PreviewApp.swift" \
  -o "$APP/WatchPreview"
cp "$WATCH_DIR/PreviewHarness/Info.plist" "$APP/Info.plist"
xcrun actool "$WATCH_DIR/Assets.xcassets" --compile "$APP" \
  --platform watchsimulator --minimum-deployment-target 10.0 --target-device watch \
  --app-icon AppIcon --output-partial-info-plist "$RUN_TMP/asset-info.plist"
codesign --force --sign - "$APP"
printf 'WATCH_PREVIEW_BUILD_READY=%s\n' "$APP"
