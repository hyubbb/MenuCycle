#!/bin/bash
# MenuCycle 설치 / 업데이트
# 다운로드 폴더에서 가장 최근에 받은 MenuCycle(zip 또는 압축 푼 폴더)을 찾아 빌드하고 설치합니다.
# 처음 한 번 실행하면 바탕화면에 'MenuCycle 업데이트' 아이콘이 생기고, 다음부터는 그걸 더블클릭하면 됩니다.
set -uo pipefail

DL="$HOME/Downloads"
TARGET="$HOME/Desktop/MenuCycle 업데이트.command"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

finish() {
  echo
  echo "(이 창은 닫아도 돼요)"
  exit "${1:-0}"
}

# 1) 처음 실행이면 바탕화면에 자기 자신을 복사 (다운로드 표시를 지워서 다음부터 바로 더블클릭 가능)
if [[ "$SELF" != "$TARGET" ]]; then
  cp "$SELF" "$TARGET" && chmod +x "$TARGET"
  xattr -d com.apple.quarantine "$TARGET" 2>/dev/null || true
  echo "✓ 바탕화면에 'MenuCycle 업데이트'를 만들었어요. 다음부터는 새 버전을 받은 뒤 그걸 더블클릭하세요."
  echo
fi

# 2) 다운로드 폴더에서 가장 최근 MenuCycle 찾기 (zip 또는 압축 푼 폴더)
newest=""
newest_t=0
shopt -s nullglob
for f in "$DL"/MenuCycle*.zip "$DL"/MenuCycle*/build.sh; do
  if [[ "$f" == *.zip ]]; then t=$(stat -f %m "$f"); else t=$(stat -f %m "$(dirname "$f")"); fi
  if (( t > newest_t )); then newest="$f"; newest_t=$t; fi
done

if [[ -z "$newest" ]]; then
  echo "✗ 다운로드 폴더에서 MenuCycle을 찾지 못했어요. 먼저 MenuCycle.zip을 받아주세요."
  finish 1
fi

if [[ "$newest" == *.zip ]]; then
  echo "▸ 사용할 파일: $(basename "$newest")"
  WORK="$(mktemp -d)"
  ditto -x -k "$newest" "$WORK"
  buildfile="$(find "$WORK" -maxdepth 3 -name build.sh | head -1)"
  if [[ -z "$buildfile" ]]; then
    echo "✗ zip 안에서 build.sh를 찾지 못했어요."
    finish 1
  fi
  SRC="$(dirname "$buildfile")"
else
  SRC="$(dirname "$newest")"
  echo "▸ 사용할 폴더: $(basename "$SRC")"
fi

# 3) 빌드 + 설치
cd "$SRC" || finish 1
if bash build.sh install; then
  echo
  echo "✓ 설치 완료. 메뉴바에서 MenuCycle을 쓰면 돼요."
  finish 0
else
  echo
  echo "✗ 빌드에 실패했어요. 위의 빨간 에러 메시지를 복사해서 Claude에게 보내주세요."
  finish 1
fi
