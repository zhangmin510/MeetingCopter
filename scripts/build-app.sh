#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MeetingCopter"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/debug/$APP_NAME"

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"

/usr/libexec/PlistBuddy \
  -c "Add :CFBundleName string $APP_NAME" \
  -c "Add :CFBundleDisplayName string $APP_NAME" \
  -c "Add :CFBundleExecutable string $APP_NAME" \
  -c "Add :CFBundleIdentifier string ai.10x.MeetingCopter" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleVersion string 1" \
  -c "Add :CFBundleShortVersionString string 1.0" \
  -c "Add :LSUIElement bool true" \
  -c "Add :NSCalendarsUsageDescription string MeetingCopter checks upcoming meetings so it can show helicopter banner reminders." \
  -c "Add :NSCalendarsFullAccessUsageDescription string MeetingCopter checks upcoming meetings so it can show helicopter banner reminders." \
  "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
