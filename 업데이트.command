#!/bin/bash
# MenuCycle 설치 / 업데이트
# 이 파일이 들어 있는 폴더의 소스로 빌드해서 /Applications 에 설치하고 실행합니다.
# (터미널에서 bash build.sh install 을 실행하는 것과 같음)
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# 예전 버전이 바탕화면에 만들어 둔 바로가기가 있으면 정리
rm -f "$HOME/Desktop/MenuCycle 업데이트.command" 2>/dev/null

if [[ ! -f build.sh ]]; then
  echo "✗ 같은 폴더에서 build.sh를 찾지 못했어요. zip을 푼 MenuCycle 폴더 안에서 실행해 주세요."
  exit 1
fi

if bash build.sh install; then
  echo
  echo "✓ 설치 완료. 메뉴바에서 MenuCycle을 쓰면 돼요. (이 창은 닫아도 돼요)"
else
  echo
  echo "✗ 빌드에 실패했어요. 위의 에러 메시지를 복사해서 Claude에게 보내주세요."
  exit 1
fi
