#!/usr/bin/env bash
set -euo pipefail

MODE="run"
APP_NAME="${APP_NAME:-IIGSDebugger}"

if [[ $# -gt 0 ]]; then
  case "$1" in
    IIGSDebugger|VideoTest|ADBTest|DiskTest)
      APP_NAME="$1"
      shift
      ;;
  esac
fi

if [[ $# -gt 0 ]]; then
  MODE="$1"
fi

BUNDLE_ID="dev.local.$APP_NAME"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/Build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild build \
  -project "$ROOT_DIR/IIGSCore.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -f "$APP_BINARY" >/dev/null
    ;;
  *)
    echo "usage: $0 [IIGSDebugger|VideoTest|ADBTest|DiskTest] [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
