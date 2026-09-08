#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/iosApp/build/DerivedData"
OUTPUT_DIR="$PROJECT_ROOT/iosApp/build/development-package"
mkdir -p "$OUTPUT_DIR"
xcodebuild -project "$PROJECT_ROOT/iosApp/iosApp.xcodeproj" -scheme NuvioTV \
  -configuration Debug -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= ARCHS=arm64 build
STAGE_DIR="$(mktemp -d "$OUTPUT_DIR/package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir "$STAGE_DIR/Payload"
cp -R "$BUILD_DIR/Build/Products/Debug-appletvos/NuvioTV.app" "$STAGE_DIR/Payload/"
# Extension signatures do not survive common free-Apple-ID sideloading tools.
rm -rf "$STAGE_DIR/Payload/NuvioTV.app/PlugIns"
(cd "$STAGE_DIR" && zip -qry "$OUTPUT_DIR/NuvioTV-Development-unsigned.ipa" Payload)
printf 'Created %s\n' "$OUTPUT_DIR/NuvioTV-Development-unsigned.ipa"
