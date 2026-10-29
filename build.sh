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

compile() { # $1 = arm64 | x86_64, $2 = 출력 파일
  swiftc -O -swift-version 5 \
    -target "$1-apple-macos13.0" \
    -framework Cocoa -framework SwiftUI -framework WebKit -framework Carbon -framework ServiceManagement \
    Sources/main.swift -o "$2"
}

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # 배포용: Apple Silicon + Intel 둘 다 들어간 파일 (GitHub Actions에서 사용)
  echo "▸ 컴파일 중 (arm64 + x86_64)…"
  mkdir -p build/tmp
  compile arm64 build/tmp/MenuCycle-arm64
  compile x86_64 build/tmp/MenuCycle-x86_64
  lipo -create build/tmp/MenuCycle-arm64 build/tmp/MenuCycle-x86_64 -output "$APP/Contents/MacOS/MenuCycle"
  rm -rf build/tmp
else
  echo "▸ 컴파일 중 ($ARCH)…"
  compile "$ARCH" "$APP/Contents/MacOS/MenuCycle"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MenuCycle</string>
  <key>CFBundleDisplayName</key><string>MenuCycle</string>
  <key>CFBundleIdentifier</key><string>local.menucycle.app</string>
  <key>CFBundleExecutable</key><string>MenuCycle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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

# 앱 아이콘 (Resources/AppIcon.svg 를 그린 .icns)
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
# 앱 안의 '최신 버전 확인'이 GitHub의 최신 빌드와 비교할 때 쓰는 커밋
COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"
if [[ -n "$COMMIT" ]]; then
  /usr/libexec/PlistBuddy -c "Add :MCBuildCommit string $COMMIT" "$APP/Contents/Info.plist"
fi

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
