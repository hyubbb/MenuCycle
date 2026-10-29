<p align="center"><img src="docs/icon.png" width="128" alt="MenuCycle 아이콘"></p>

# MenuCycle

**기술 스택** · Swift 5 · AppKit · SwiftUI · WebKit (WKWebView) · Carbon (전역 단축키) · ServiceManagement · URLSession + GitHub REST API · GitHub Actions (CI/CD) — 외부 라이브러리 없이 Apple 기본 프레임워크만 사용

| 분야 | 사용 기술 | 쓰인 곳 |
|---|---|---|
| 언어 | Swift 5 | 앱 전체 (단일 파일, Xcode 프로젝트 없이 `swiftc`로 빌드) |
| UI | AppKit — `NSStatusItem`, `NSPanel`, `NSStackView`, `NSPopover`, `NSMenu` | 메뉴바 아이콘, 떠 있는 창, 탭 막대(드래그 정렬), 투명도 슬라이더, 우클릭 메뉴 |
| UI | SwiftUI — `ObservableObject`, `Form`, `TabView`, `List`, `NSViewRepresentable` | 설정 창, 방문 기록 창, 단축키 입력 칸 |
| 웹 | WebKit — `WKWebView`, `WKNavigationDelegate`, `WKUIDelegate`, `WKDownload`, `WKUserScript`, `WKScriptMessageHandler`, `WKURLSchemeHandler`, `WKWebsiteDataStore` | 탭별 웹페이지, 새 창·로그인 팝업 처리, 다운로드, 음소거·우클릭 링크 스크립트, 커스텀 스킴(`menucycle://`) 시작 페이지, 시크릿 탭(비영구 저장소) |
| 시스템 | Carbon `RegisterEventHotKey` | 손쉬운 사용 권한 없이 동작하는 전역 단축키 |
| 시스템 | ServiceManagement `SMAppService` | 로그인 시 자동 실행 |
| 시스템 | Foundation — `URLSession`, `Codable`, KVO, `Process` | GitHub API로 업데이트 확인·다운로드·자체 교체, 설정·기록 JSON 저장 |
| 배포 | bash, `codesign`, `lipo`(Universal Binary), `hdiutil`(DMG), GitHub Actions(macOS runner), GitHub Releases | 빌드 스크립트, Apple Silicon + Intel 빌드, 푸시할 때마다 자동 빌드·릴리스 |

메뉴바에서 웹페이지를 띄워 쓰는 macOS 앱입니다. [MenubarX](https://menubarx.app)에서 아이디어를 얻었고, **단축키 하나로 여러 탭을 순환**하는 기능을 중심으로 만들었습니다.

- 단축키로 창을 열고 닫으며, 다른 단축키로 1번 → 2번 → 3번 탭을 돌아가며 볼 수 있습니다
- 탭마다 웹페이지가 따로 살아 있어 전환해도 로그인, 스크롤 위치, 입력 중인 내용이 유지됩니다
- 주소창, 탭, 다운로드, 찾기, 확대/축소, PIP, 음소거 같은 브라우저 기본 기능을 갖췄습니다
- 설정 창에서 단축키와 동작을 바꿀 수 있습니다

> Safari와 같은 WebKit 엔진을 쓰며, 별도 서버 없이 Mac 안에서만 동작합니다.

---

## 요구 사항

- macOS 13 (Ventura) 이상
- 소스에서 직접 빌드할 때만: Xcode Command Line Tools (`xcode-select --install`)

## 다운로드 (빌드 없이 바로 설치)

[**Releases → 최신 빌드**](https://github.com/hyubbb/MenuCycle/releases/latest)에서 `MenuCycle.dmg`를 받아 열고, MenuCycle을 **Applications** 폴더로 끌어다 놓으세요.
macOS 13 이상이면 Apple Silicon과 Intel Mac 모두에서 동작합니다.

처음 열 때 **"확인되지 않은 개발자"** 경고가 뜨면 다음 중 하나를 하세요.
- 시스템 설정 → 개인정보 보호 및 보안 → 아래쪽 **그래도 열기**
- 터미널에서 `xattr -cr /Applications/MenuCycle.app` 실행 후 다시 열기

> `main`에 코드가 올라올 때마다 GitHub Actions가 앱을 빌드해서 최신 빌드를 자동으로 바꿉니다. 버전을 고정해 배포하려면 `git tag v1.0 && git push origin v1.0`처럼 태그를 올리세요.

## 소스에서 빌드해 설치

```bash
git clone https://github.com/hyubbb/MenuCycle.git
cd MenuCycle
bash build.sh install
```

`build.sh install`은 앱을 빌드해 `/Applications/MenuCycle.app`에 복사한 뒤 실행합니다. 이미 실행 중이면 종료하고 새 버전으로 바꿉니다.

| 명령 | 동작 |
|---|---|
| `bash build.sh` | `build/MenuCycle.app` 빌드만 |
| `bash build.sh install` | 빌드 → `/Applications`에 설치 → 실행 |

### zip으로 받은 경우

압축을 푼 `MenuCycle` 폴더 안의 **`업데이트.command`를 더블클릭**하세요. 터미널이 열리면서 위의 `bash build.sh install`을 대신 실행합니다. 처음 설치할 때와 업데이트할 때 모두 같은 방법을 씁니다.

---

## 사용법

메뉴바에 아이콘이 생깁니다. **좌클릭**하면 창이 열리고 닫히며, **우클릭**하면 탭 목록과 빠른 설정, 설정 메뉴가 나옵니다.

### 전역 단축키

어느 앱을 쓰고 있든 동작합니다. 설정에서 바꿀 수 있습니다.

| 동작 | 기본 키 |
|---|---|
| 열기 / 닫기 | `⌃⌥M` |
| 다음 탭 / 이전 탭 | `⌃⌥]` / `⌃⌥[` |

### 창 안에서 쓰는 단축키

| 동작 | 키 |
|---|---|
| 새 탭 / 탭 닫기 / 닫은 탭 다시 열기 | `⌘T` / `⌘W` / `⌘⇧T` |
| 새 시크릿 탭 | `⌘⇧N` |
| 방문 기록 | `⌘Y` |
| N번 탭으로 | `⌘1` ~ `⌘9` |
| 다음 / 이전 탭 | `⌃Tab` / `⌃⇧Tab` |
| 주소창 | `⌘L` |
| 뒤로 / 앞으로 / 새로고침 | `⌘[` / `⌘]` / `⌘R` |
| 페이지에서 찾기 / 다음 / 이전 | `⌘F` / `⌘G` / `⌘⇧G` |
| 확대 / 축소 / 원래 크기 | `⌘+` / `⌘-` / `⌘0` |
| 현재 탭 음소거 | `⌘⇧M` |
| 영상 PIP (화면 속 화면) | `⌘⇧P` |
| 창 닫기 | `Esc` |
| 설정 | `⌘,` |

### 화면 구성

```
┌──────────────────────────────────────────────┐
│ [ 1 ] [ 2 ] [ 3 ]                         [+] │  ← 탭: 번호만 표시(설정에서 이름 표시 가능), 클릭·끌기·우클릭
│                                              │
│                 웹페이지                       │
│                                              │
│ ‹ › ↻ ⌂  [ 주소 또는 검색어        ] 🔊 🖥 ◐ ⋯ ⚙ │  ← 주소창 (설정 → 창에서 위/아래 선택)
└──────────────────────────────────────────────┘
```

| 버튼 | 기능 |
|---|---|
| ⌂ | 홈: 설정에서 등록한 탭은 등록한 주소로, `+`로 만든 탭은 시작 페이지로 |
| 🔊 | 현재 탭 음소거 |
| 🖥 | 화면 종류: PC / iPhone / iPad / Android / 직접 입력한 User-Agent |
| ◐ | 창 투명도 (세로 슬라이더, 30~100%) |
| ⋯ | PIP, 찾기, 방문 기록, 새 시크릿 탭, 확대/축소, 자동 새로고침, 창 닫을 때 일시정지, 다운로드 폴더 |
| ⚙ | 설정 |

`+`로 만든 탭은 **시작 페이지**로 열립니다. 검색창과 자주 가는 사이트 바로가기(네이버, Google, Instagram, YouTube, YouTube Music, Spotify, ChatGPT, Claude, Gemini)가 있고, 바로가기는 설정 → 새 탭에서 추가·삭제·순서 변경할 수 있습니다. 탭 이름과 주소는 보고 있는 사이트를 따라갑니다. 다음에 앱을 켜도 마지막으로 보던 사이트로 열립니다.

---

## 기능

**탭**
- 단축키로 탭 순환, 드래그로 순서 변경
- 탭에는 기본으로 번호만 보임 (보고 있는 사이트가 드러나지 않게). 설정 → 창에서 이름 표시를 켤 수 있음
- 탭마다 화면 종류(PC/모바일), 확대 비율, 음소거, 자동 새로고침(1~60분) 따로 지정
- `⌘W`로 닫은 탭은 `⌘⇧T`로 최근 20개까지 되살릴 수 있음

**브라우저**
- 주소창: 주소를 입력하면 이동하고, 검색어를 입력하면 Google / 네이버 / DuckDuckGo로 검색
- 파일 다운로드: 다운로드 폴더에 저장되며, 같은 이름이 있으면 `이름 (2)`로 저장
- 영상 전체화면, PIP
- 새 창으로 열리는 링크(검색 결과, 우클릭 → 새 창, 로그인 팝업)는 항상 앱 안 새 탭으로. 로그인 팝업은 끝나면 탭이 자동으로 닫히고 원래 탭으로 돌아감
- `⌘`+클릭: 뒤쪽 새 탭으로 열기
- 링크를 눌러도 다른 앱(예: 크롬·Safari로 설치한 유튜브 웹 앱)으로 넘어가지 않고 앱 안에서 열림
- `⌥`(Option)+클릭 또는 링크 우클릭 → **기본 브라우저에서 열기**: 시스템 브라우저(Safari/Chrome)로 열기

**업데이트**
- 설정 → 일반 → **최신 버전 확인**: GitHub의 최신 빌드와 비교하고 바뀐 점을 보여줌
- **지금 업데이트**: 새 버전을 내려받아 교체한 뒤 앱을 다시 실행 (DMG를 다시 받을 필요 없음)
- 시작할 때와 하루마다 자동 확인, 새 버전이 있으면 메뉴바 아이콘에 ＋ 표시되고 우클릭 메뉴에 설치 항목이 생김

**방문 기록 · 시크릿 탭**
- 방문한 페이지를 기록하고(최근 5000개), 주소창에 입력하면 자주 가는 사이트를 Safari처럼 자동완성
- `⌘Y` 기록 창: 검색, 현재 탭이나 새 탭에서 열기, 항목 삭제, 지난 1시간·오늘·전체 지우기
- 기록 남기기는 설정 → 일반에서 끌 수 있음
- 시크릿 탭(`⌘⇧N`, 🕶 표시, 주소창 보라색): 기록·쿠키를 남기지 않고 앱을 끄면 사라짐. 시크릿 탭에서 연 링크도 시크릿 탭

**창**
- 열리는 위치: 메뉴바 아이콘 아래 / 화면 가운데 / 마지막으로 옮긴 위치
- 크기 조절, 투명도(30~100%), 항상 위에 표시, 모든 데스크탑(Spaces)에서 표시
- 닫는 방법을 각각 켜고 끌 수 있음: 바깥 클릭, `Esc`
- `⌘W` 동작 선택: 탭 닫기(기본, 마지막 탭이면 창 닫기) / 창 닫기 / 아무 동작 안 함

**메모리 · 소리**
- 일정 시간 안 본 탭을 메모리에서 내리기(10분~3시간). 다시 열면 마지막 주소로 새로 불러오며, 재생 중인 탭과 현재 탭은 내리지 않음
- 창을 닫을 때 재생 중인 영상·음악 일시정지

## 설정 창

| 탭 | 항목 |
|---|---|
| 일반 | 업데이트 확인·설치, 로그인 시 자동 실행, 방문 기록 남기기·보기, 마지막 탭 기억, 검색 엔진, 직접 입력 User-Agent, 메모리 해제, 창 닫을 때 일시정지 |
| 단축키·닫기 | 단축키 녹화, 열기/닫기 같은 키 사용 여부, `⌘W` 동작, 닫는 방법 |
| 창 | 위치, 크기, 탭 막대·탭 이름·주소창 표시, 주소창 위치(위/아래), 가운데 알림 표시, 항상 위, 모든 데스크탑, 투명도 |
| 페이지 | 탭 추가·삭제·이름·주소·화면 종류·자동 새로고침, 드래그로 순서 변경 |
| 새 탭 | 시작 페이지 바로가기 추가·삭제·순서 변경, 기본 목록으로 되돌리기 |

설정은 `~/Library/Application Support/MenuCycle/config.json`에 저장되며, 직접 고친 뒤 설정 → 일반 → **설정 파일 다시 불러오기**로 반영할 수 있습니다.

---

## 삭제

```bash
pkill -x MenuCycle
rm -rf /Applications/MenuCycle.app
rm -rf ~/Library/Application\ Support/MenuCycle
rm -rf ~/Library/WebKit/local.menucycle.app ~/Library/Caches/local.menucycle.app ~/Library/HTTPStorages/local.menucycle.app
defaults delete local.menucycle.app 2>/dev/null
```

명령은 위에서부터 차례로 앱을 종료하고, 앱을 지우고, 설정과 방문 기록을 지우고, 웹사이트 로그인 정보와 캐시를 지우고, 마지막 탭 기록을 지웁니다. 로그인 시 자동 실행을 켜 두었다면 삭제하기 전에 설정에서 먼저 끄세요.

## 프로젝트 구조

```
MenuCycle/
├── Sources/main.swift   # 앱 전체 (AppKit + SwiftUI 설정 창 + WebKit)
├── Resources/           # 앱 아이콘(AppIcon.svg → AppIcon.icns), 메뉴바 아이콘 원본(MenuBarIcon.svg)
├── build.sh             # swiftc로 빌드 → .app 번들 생성 → ad-hoc 서명 (install 시 설치·실행, UNIVERSAL=1이면 Intel+Apple Silicon)
├── 업데이트.command      # 더블클릭하면 build.sh install 실행
├── .github/workflows/release.yml  # 푸시할 때마다 앱 빌드 → Releases에 DMG 업로드
└── README.md
```

Xcode 프로젝트 없이 `swiftc` 한 번으로 빌드합니다. 전역 단축키는 Carbon `RegisterEventHotKey`를 쓰기 때문에 손쉬운 사용 권한이 필요 없습니다.

## 알려진 제한

- PIP는 사이트에 따라 막힐 수 있습니다
- 음소거는 페이지 안에 따로 들어간 영상 플레이어(iframe)에는 적용되지 않을 수 있습니다
- 웹 푸시 알림, 광고 차단, 탭을 별도 창으로 떼어내기는 아직 지원하지 않습니다
