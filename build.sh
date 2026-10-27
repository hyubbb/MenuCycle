#!/bin/bash
# MenuCycle 빌드 스크립트 (macOS 13+, Xcode Command Line Tools 필요)
# 사용법:  ./build.sh          → build/MenuCycle.app 생성
#          ./build.sh install  → /Applications 로 복사 후 실행
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MenuCycle.app"
ARCH="$(uname -m)"   # arm64 또는 x86_64

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc가 없습니다. 먼저 실행하세요:  xcode-select --install"
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 컴파일 중 ($ARCH)…"
swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -framework Cocoa -framework SwiftUI -framework WebKit -framework Carbon -framework ServiceManagement \
  Sources/main.swift -o "$APP/Contents/MacOS/MenuCycle"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MenuCycle</string>
  <key>CFBundleDisplayName</key><string>MenuCycle</string>
  <key>CFBundleIdentifier</key><string>local.menucycle.app</string>
  <key>CFBundleExecutable</key><string>MenuCycle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>웹페이지에서 카메라를 사용할 때 필요합니다.</string>
  <key>NSMicrophoneUsageDescription</key><string>웹페이지에서 마이크를 사용할 때 필요합니다.</string>
</dict>
</plist>
PLIST

echo "▸ 서명 중 (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ 완료: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x MenuCycle 2>/dev/null || true
  rm -rf /Applications/MenuCycle.app
  cp -R "$APP" /Applications/
  open /Applications/MenuCycle.app
  echo "✓ /Applications/MenuCycle.app 설치 후 실행했습니다."
fi
