#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Folbi"
SCHEME_NAME="Folbi"
BUNDLE_ID="com.dimon.folbi"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
CONFIGURATION="Debug"

if [[ "$MODE" == "--install" || "$MODE" == "install" ]]; then
  CONFIGURATION="Release"
fi

APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INSTALL_BUNDLE="${HOME}/Applications/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild build -quiet \
  -project "$ROOT_DIR/Folbi.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO

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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --install|install)
    mkdir -p "$(dirname "$INSTALL_BUNDLE")"
    /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"
    /usr/bin/open -n "$INSTALL_BUNDLE"
    echo "$INSTALL_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--install]" >&2
    exit 2
    ;;
esac
