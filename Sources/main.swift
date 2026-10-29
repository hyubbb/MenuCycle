// MenuCycle — MenubarX 스타일 메뉴바 브라우저 + 단축키 페이지 순환
// macOS 13+ / Swift 5

import Cocoa
import SwiftUI
import WebKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - 키 코드

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
    "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
    "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
    "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
    "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
    "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "enter": kVK_Return,
    "esc": kVK_Escape, "`": kVK_ANSI_Grave, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
    "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon,
    "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
    "\\": kVK_ANSI_Backslash,
    "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
    "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
    "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
]

let specialKeyNames: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "Esc",
    kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
    kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
]

let fKeyCodes: Set<Int> = [
    kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
    kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
]

/// 예전 config.json의 "ctrl+opt+m" 같은 문자열을 읽기 위한 함수
func parseHotkey(_ s: String) -> KeyCombo? {
    var mods: UInt32 = 0
    var key: UInt32?
    for raw in s.lowercased().split(separator: "+") {
        let part = raw.trimmingCharacters(in: .whitespaces)
        switch part {
        case "cmd", "command", "⌘": mods |= UInt32(cmdKey)
        case "opt", "option", "alt", "⌥": mods |= UInt32(optionKey)
        case "ctrl", "control", "⌃": mods |= UInt32(controlKey)
        case "shift", "⇧": mods |= UInt32(shiftKey)
        default:
            guard let k = keyCodes[part] else { return nil }
            key = UInt32(k)
        }
    }
    guard let key else { return nil }
    return KeyCombo(keyCode: key, modifiers: mods)
}

struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon 형식

    static func make(_ code: Int, _ mods: Int) -> KeyCombo {
        KeyCombo(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCombo.name(for: Int(keyCode))
    }

    static func name(for code: Int) -> String {
        if let n = specialKeyNames[code] { return n }
        if let n = keyCodes.first(where: { $0.value == code })?.key { return n.uppercased() }
        return "#\(code)"
    }
}

extension KeyCombo {
    init(event: NSEvent) {
        var m: UInt32 = 0
        let f = event.modifierFlags
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: m)
    }
}

// MARK: - 설정

enum WindowPosition: String, Codable, CaseIterable, Identifiable {
    case statusItem, center, remembered
    var id: String { rawValue }
    var title: String {
        switch self {
        case .statusItem: return "메뉴바 아이콘 아래"
        case .center: return "화면 가운데"
        case .remembered: return "마지막으로 옮긴 위치"
        }
    }
}

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, naver, duckduckgo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: return "Google"
        case .naver: return "네이버"
        case .duckduckgo: return "DuckDuckGo"
        }
    }
    /// 검색 엔진 첫 화면 (+로 만든 탭의 홈)
    var homeURL: String {
        switch self {
        case .google: return "https://www.google.com"
        case .naver: return "https://www.naver.com"
        case .duckduckgo: return "https://duckduckgo.com"
        }
    }

    func searchURL(_ q: String) -> URL? {
        var c: URLComponents?
        switch self {
        case .google:
            c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "q", value: q)]
        case .naver:
            c = URLComponents(string: "https://search.naver.com/search.naver")
            c?.queryItems = [URLQueryItem(name: "query", value: q)]
        case .duckduckgo:
            c = URLComponents(string: "https://duckduckgo.com/")
            c?.queryItems = [URLQueryItem(name: "q", value: q)]
        }
        return c?.url
    }
}

enum CmdWAction: String, Codable, CaseIterable, Identifiable {
    case closeTab, hideWindow, nothing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .closeTab: return "현재 탭 닫기 (브라우저처럼)"
        case .hideWindow: return "창 닫기"
        case .nothing: return "아무 동작 안 함"
        }
    }
}

enum NewWindowBehavior: String, Codable, CaseIterable, Identifiable {
    case newTab, sameView // (더 이상 설정에서 고르지 않음. 새 창 링크는 항상 새 탭)
    var id: String { rawValue }
}

let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
let iphoneUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
let ipadUA = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
let androidUA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36"

enum DeviceMode: String, Codable, CaseIterable, Identifiable {
    case desktop, iphone, ipad, android, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: return "PC (Mac)"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .android: return "Android"
        case .custom: return "직접 입력한 User-Agent"
        }
    }
    var short: String {
        switch self {
        case .desktop: return "PC"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .android: return "Android"
        case .custom: return "직접 입력"
        }
    }
    var symbol: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .iphone, .android: return "iphone"
        case .ipad: return "ipad"
        case .custom: return "slider.horizontal.3"
        }
    }
    func userAgent(custom: String) -> String {
        switch self {
        case .desktop: return desktopUA
        case .iphone: return iphoneUA
        case .ipad: return ipadUA
        case .android: return androidUA
        case .custom:
            let c = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? desktopUA : c
        }
    }
}

let refreshChoices = [0, 1, 5, 10, 30, 60]

/// 새 탭 시작 페이지의 바로가기
struct QuickLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

extension QuickLink {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
    }
}

let startPageURL = "menucycle://newtab"

struct PageConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var device: DeviceMode = .desktop
    var autoName: Bool = false // true면 탭 이름·주소가 보고 있는 사이트를 따라감 (+ 로 만든 탭)
    var muted: Bool = false
    var zoom: Double = 1.0
    var refreshMinutes: Int = 0 // 0 = 자동 새로고침 끔
    var incognito: Bool = false // 시크릿 탭: 쿠키·기록을 남기지 않고, 앱을 끄면 사라짐
}

extension PageConfig {
    private enum LegacyKeys: String, CodingKey { case mobile }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "페이지"
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? "https://"
        let wasMobile = (try? legacy.decodeIfPresent(Bool.self, forKey: .mobile)) ?? false
        device = (try? c.decodeIfPresent(DeviceMode.self, forKey: .device)) ?? (wasMobile ? .iphone : .desktop)
        autoName = (try? c.decodeIfPresent(Bool.self, forKey: .autoName)) ?? false
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        zoom = (try? c.decodeIfPresent(Double.self, forKey: .zoom)) ?? 1.0
        refreshMinutes = (try? c.decodeIfPresent(Int.self, forKey: .refreshMinutes)) ?? 0
        incognito = (try? c.decodeIfPresent(Bool.self, forKey: .incognito)) ?? false
    }
}

struct AppConfig: Codable, Equatable {
    var version = 2

    // 단축키
    var openKey: KeyCombo? = KeyCombo.make(kVK_ANSI_M, controlKey | optionKey)
    var sameKeyToggle = true                 // 열기 키를 다시 누르면 닫힘
    var closeKey: KeyCombo? = nil            // sameKeyToggle == false 일 때
    var openKeyWhileOpenNext = true          // sameKeyToggle == false 일 때: 열린 상태에서 열기 키 → 다음 페이지
    var nextKey: KeyCombo? = KeyCombo.make(kVK_ANSI_RightBracket, controlKey | optionKey)
    var prevKey: KeyCombo? = KeyCombo.make(kVK_ANSI_LeftBracket, controlKey | optionKey)

    // 닫기
    var closeOnBlur = true
    var closeOnEsc = true
    var closeOnCmdW = true // 예전 설정 (지금은 cmdWAction 사용)
    var cmdWAction: CmdWAction = .closeTab

    // 창
    var position: WindowPosition = .statusItem
    var savedOrigin: [Double]? = nil
    var width: Double = 420
    var height: Double = 680
    var alwaysOnTop = true
    var allSpaces = true
    var showTabBar = true
    var showTabNames = false // 탭에 페이지 이름 표시 (기본: 번호만)
    var showAddressBar = true
    var addressBarAtBottom = true // 주소창 섹션을 창 아래쪽에
    var showHUD = true

    // 일반
    var rememberLastPage = true
    var searchEngine: SearchEngine = .google
    var quickLinks: [QuickLink] = AppConfig.defaultQuickLinks
    var newWindow: NewWindowBehavior = .newTab
    var customUserAgent = ""

    // 메모리·소리
    var unloadMinutes = 0       // 0 = 끔. N분 동안 안 본 탭은 메모리에서 내림
    var pauseOnClose = false    // 창을 닫으면 재생 중인 영상·음악 일시정지
    var recordHistory = true    // 방문 기록 남기기
    var autoCheckUpdates = true // 시작할 때(이후 하루마다) 새 버전 확인

    // 모양
    var opacity: Double = 1.0

    var pages: [PageConfig] = [AppConfig.googlePage()]

    static let defaultQuickLinks: [QuickLink] = [
        QuickLink(name: "네이버", url: "https://www.naver.com"),
        QuickLink(name: "Google", url: "https://www.google.com"),
        QuickLink(name: "Instagram", url: "https://www.instagram.com"),
        QuickLink(name: "YouTube", url: "https://www.youtube.com"),
        QuickLink(name: "YouTube Music", url: "https://music.youtube.com"),
        QuickLink(name: "Spotify", url: "https://open.spotify.com"),
        QuickLink(name: "ChatGPT", url: "https://chatgpt.com"),
        QuickLink(name: "Claude", url: "https://claude.ai"),
        QuickLink(name: "Gemini", url: "https://gemini.google.com"),
    ]

    static func googlePage() -> PageConfig {
        PageConfig(name: "새 탭", url: startPageURL, autoName: true)
    }
}

extension AppConfig {
    private enum LegacyKeys: String, CodingKey { case hotkey, prevHotkey, hideOnBlur }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let isV2 = c.contains(.version)

        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)) ?? d
        }
        // v2에선 키가 없으면 '비어 있음', 예전 파일이면 기본값
        func key(_ k: CodingKeys, _ d: KeyCombo?) -> KeyCombo? {
            if c.contains(k) { return try? c.decodeIfPresent(KeyCombo.self, forKey: k) }
            return isV2 ? nil : d
        }

        openKey = key(.openKey, openKey)
        if !c.contains(.openKey), let s = try? legacy.decodeIfPresent(String.self, forKey: .hotkey),
           let k = parseHotkey(s) { openKey = k }
        sameKeyToggle = v(.sameKeyToggle, sameKeyToggle)
        closeKey = key(.closeKey, closeKey)
        openKeyWhileOpenNext = v(.openKeyWhileOpenNext, openKeyWhileOpenNext)
        nextKey = key(.nextKey, nextKey)
        prevKey = key(.prevKey, prevKey)
        if !c.contains(.prevKey), let s = try? legacy.decodeIfPresent(String.self, forKey: .prevHotkey),
           let k = parseHotkey(s) { prevKey = k }

        let legacyBlur = (try? legacy.decodeIfPresent(Bool.self, forKey: .hideOnBlur)) ?? closeOnBlur
        closeOnBlur = v(.closeOnBlur, legacyBlur)
        closeOnEsc = v(.closeOnEsc, closeOnEsc)
        closeOnCmdW = v(.closeOnCmdW, closeOnCmdW)
        cmdWAction = v(.cmdWAction, cmdWAction)

        position = v(.position, position)
        savedOrigin = try? c.decodeIfPresent([Double].self, forKey: .savedOrigin)
        width = v(.width, width)
        height = v(.height, height)
        alwaysOnTop = v(.alwaysOnTop, alwaysOnTop)
        allSpaces = v(.allSpaces, allSpaces)
        showTabBar = v(.showTabBar, showTabBar)
        showTabNames = v(.showTabNames, showTabNames)
        showAddressBar = v(.showAddressBar, showAddressBar)
        addressBarAtBottom = v(.addressBarAtBottom, addressBarAtBottom)
        showHUD = v(.showHUD, showHUD)

        rememberLastPage = v(.rememberLastPage, rememberLastPage)
        searchEngine = v(.searchEngine, searchEngine)
        quickLinks = v(.quickLinks, quickLinks)
        newWindow = v(.newWindow, newWindow)
        customUserAgent = v(.customUserAgent, customUserAgent)
        unloadMinutes = v(.unloadMinutes, unloadMinutes)
        pauseOnClose = v(.pauseOnClose, pauseOnClose)
        recordHistory = v(.recordHistory, recordHistory)
        autoCheckUpdates = v(.autoCheckUpdates, autoCheckUpdates)
        opacity = v(.opacity, opacity)
        pages = v(.pages, pages)
        version = 2
    }

    func hotkeysDiffer(from o: AppConfig) -> Bool {
        openKey != o.openKey || sameKeyToggle != o.sameKeyToggle || closeKey != o.closeKey
            || nextKey != o.nextKey || prevKey != o.prevKey
    }
}

enum ConfigStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuCycle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: url) {
            do {
                return try JSONDecoder().decode(AppConfig.self, from: data)
            } catch {
                showAlert("config.json을 읽지 못했습니다", "기본 설정으로 실행합니다.\n\(error.localizedDescription)")
                return AppConfig()
            }
        }
        let cfg = AppConfig()
        save(cfg)
        return cfg
    }

    static func save(_ cfg: AppConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        var cfg = cfg
        cfg.pages = cfg.pages.filter { !$0.incognito } // 시크릿 탭은 저장하지 않음
        if let data = try? enc.encode(cfg) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

func showAlert(_ title: String, _ text: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.runModal()
}

// MARK: - 전역 단축키 (Carbon, 손쉬운 사용 권한 불필요)

final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    let status: OSStatus

    init(combo: KeyCombo, id: UInt32, handler: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        HotKey.handlers[id] = handler
        let hkID = EventHotKeyID(signature: OSType(0x4D43_5943), id: id) // 'MCYC'
        status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let id = hkID.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: - 단축키 입력 칸

final class HotkeyRecorderView: NSView {
    /// 녹화 중에는 전역 단축키를 잠시 해제해야 같은 키를 다시 입력할 수 있음
    static var onRecordingChanged: ((Bool) -> Void)?

    var combo: KeyCombo? { didSet { needsDisplay = true } }
    var onChange: ((KeyCombo?) -> Void)?
    private(set) var isRecording = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !isRecording, combo != nil, p.x > bounds.maxX - 24 {
            combo = nil
            onChange?(nil)
            return
        }
        if isRecording { stop(releaseFocus: true) } else { start() }
    }

    private func start() {
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        HotkeyRecorderView.onRecordingChanged?(true)
    }

    private func stop(releaseFocus: Bool) {
        guard isRecording else { return }
        isRecording = false
        HotkeyRecorderView.onRecordingChanged?(false)
        if releaseFocus, window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func resignFirstResponder() -> Bool {
        stop(releaseFocus: false)
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording { record(event); return true }
        return super.performKeyEquivalent(with: event)
    }

    private func record(_ e: NSEvent) {
        let code = Int(e.keyCode)
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty && code == kVK_Escape { stop(releaseFocus: true); return }
        if flags.isEmpty && (code == kVK_Delete || code == kVK_ForwardDelete) {
            combo = nil
            onChange?(nil)
            stop(releaseFocus: true)
            return
        }
        let isF = fKeyCodes.contains(code)
        if !isF && (flags.isEmpty || flags == .shift) { NSSound.beep(); return }
        let c = KeyCombo(event: e)
        combo = c
        onChange?(c)
        stop(releaseFocus: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let hasKey = combo != nil && !isRecording
        let text = isRecording ? "키 조합을 누르세요…" : (combo?.display ?? "클릭해서 설정")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: hasKey ? .semibold : .regular),
            .foregroundColor: (combo == nil && !isRecording) ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))

        if hasKey {
            let x = NSAttributedString(string: "✕", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
            let xs = x.size()
            x.draw(at: NSPoint(x: bounds.maxX - 13 - xs.width / 2, y: (bounds.height - xs.height) / 2))
        }
    }
}

struct HotkeyField: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.combo = combo
        let b = $combo
        v.onChange = { b.wrappedValue = $0 }
        return v
    }

    func updateNSView(_ v: HotkeyRecorderView, context: Context) {
        let b = $combo
        v.onChange = { b.wrappedValue = $0 }
        if !v.isRecording && v.combo != combo { v.combo = combo }
    }
}

// MARK: - 설정 창 (SwiftUI)

final class SettingsModel: ObservableObject {
    @Published var config: AppConfig {
        didSet { if config != oldValue { onChange?() } }
    }
    @Published var hotkeyErrors: [String] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var updateStatus = ""
    @Published var updateAvailable = false
    @Published var updateBusy = false
    @Published var updateNotes: [String] = []
    var checkUpdate: (() -> Void)?
    var installUpdate: (() -> Void)?

    var currentVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let c = (Bundle.main.object(forInfoDictionaryKey: "MCBuildCommit") as? String ?? "")
        return c.count >= 7 ? "\(v) (\(c.prefix(7)))" : v
    }

    var onChange: (() -> Void)?
    var openConfigFile: (() -> Void)?
    var openHistory: (() -> Void)?
    var reloadConfigFile: (() -> Void)?

    init(config: AppConfig) { self.config = config }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "자동 실행 설정 실패: \(error.localizedDescription) (앱을 /Applications 에 두고 다시 시도하세요)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func addPage() {
        config.pages.append(PageConfig(name: "새 페이지", url: "https://"))
    }

    func removePage(_ id: UUID) {
        config.pages.removeAll { $0.id == id }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            generalTab.tabItem { Label("일반", systemImage: "gearshape") }
            keysTab.tabItem { Label("단축키·닫기", systemImage: "keyboard") }
            windowTab.tabItem { Label("창", systemImage: "macwindow") }
            pagesTab.tabItem { Label("페이지", systemImage: "list.bullet") }
            quickLinksTab.tabItem { Label("새 탭", systemImage: "square.grid.3x3") }
        }
        .padding(12)
        .frame(width: 700, height: 620)
    }

    // 일반
    var generalTab: some View {
        Form {
            Section("업데이트") {
                LabeledContent("현재 버전", value: model.currentVersion)
                HStack(spacing: 10) {
                    Button("최신 버전 확인") { model.checkUpdate?() }
                        .disabled(model.updateBusy)
                    if model.updateAvailable {
                        Button("지금 업데이트") { model.installUpdate?() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.updateBusy)
                    }
                    if model.updateBusy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if !model.updateStatus.isEmpty {
                    Text(model.updateStatus).font(.caption)
                        .foregroundStyle(model.updateAvailable ? Color.accentColor : Color.secondary)
                }
                if model.updateAvailable && !model.updateNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("바뀐 점").font(.caption).bold()
                        ForEach(Array(model.updateNotes.prefix(8).enumerated()), id: \.offset) { _, n in
                            Text("• " + n).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("시작할 때 자동으로 새 버전 확인", isOn: $model.config.autoCheckUpdates)
            }
            Section("시작") {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                if let e = model.loginError {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
                Toggle("다시 열 때 마지막으로 보던 페이지 표시 (끄면 항상 1번)", isOn: $model.config.rememberLastPage)
            }
            Section("브라우저") {
                Picker("주소창 검색 엔진", selection: $model.config.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
                }
                Text("새 창으로 열리는 링크는 앱 안 새 탭으로 열립니다. 시스템 브라우저로 열려면 링크를 ⌥(Option)+클릭하거나 우클릭 → '기본 브라우저에서 열기'.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("직접 입력 User-Agent") {
                    TextField("화면 종류를 '직접 입력'으로 고른 탭에 사용", text: $model.config.customUserAgent)
                        .frame(width: 300)
                }
                Text("파일은 다운로드 폴더에 저장됩니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("방문 기록") {
                Toggle("방문 기록 남기기 (주소창 자동완성에 사용)", isOn: $model.config.recordHistory)
                HStack {
                    Button("방문 기록 보기 · 지우기…") { model.openHistory?() }
                    Spacer()
                }
                Text("시크릿 탭(⌘⇧N)은 기록·쿠키를 남기지 않고, 앱을 끄면 사라집니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("메모리 · 소리") {
                Picker("안 본 탭을 메모리에서 내리기", selection: $model.config.unloadMinutes) {
                    Text("끔").tag(0)
                    Text("10분 후").tag(10)
                    Text("30분 후").tag(30)
                    Text("1시간 후").tag(60)
                    Text("3시간 후").tag(180)
                }
                Text("내린 탭은 다시 볼 때 마지막 주소로 새로 불러옵니다. 재생 중인 탭, 자동 새로고침 탭, 현재 탭은 내리지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("창을 닫으면 재생 중인 영상·음악 일시정지", isOn: $model.config.pauseOnClose)
            }
            Section("고급") {
                HStack {
                    Button("설정 파일 열기") { model.openConfigFile?() }
                    Button("설정 파일 다시 불러오기") { model.reloadConfigFile?() }
                    Spacer()
                    Button("MenuCycle 종료") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // 단축키 · 닫기
    var keysTab: some View {
        Form {
            Section("전역 단축키 (어느 앱에서든 동작)") {
                LabeledContent(model.config.sameKeyToggle ? "열기 / 닫기" : "열기") {
                    HotkeyField(combo: $model.config.openKey).frame(width: 170, height: 24)
                }
                Toggle("열기와 닫기를 같은 키로 (열린 상태에서 다시 누르면 닫힘)", isOn: $model.config.sameKeyToggle)
                if !model.config.sameKeyToggle {
                    LabeledContent("닫기") {
                        HotkeyField(combo: $model.config.closeKey).frame(width: 170, height: 24)
                    }
                    Picker("열린 상태에서 열기 키를 누르면", selection: $model.config.openKeyWhileOpenNext) {
                        Text("다음 페이지로 전환").tag(true)
                        Text("아무 동작 안 함").tag(false)
                    }
                }
                LabeledContent("다음 페이지") {
                    HotkeyField(combo: $model.config.nextKey).frame(width: 170, height: 24)
                }
                LabeledContent("이전 페이지") {
                    HotkeyField(combo: $model.config.prevKey).frame(width: 170, height: 24)
                }
                ForEach(model.hotkeyErrors, id: \.self) { e in
                    Text("⚠️ " + e).font(.caption).foregroundStyle(.red)
                }
                Text("칸을 클릭한 뒤 키 조합을 누르세요.  ⌫ 지우기 · Esc 취소 · ✕ 클릭해도 지워짐")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("닫는 방법") {
                Toggle("다른 곳을 클릭하면 닫기", isOn: $model.config.closeOnBlur)
                Toggle("Esc 키로 바로 닫기", isOn: $model.config.closeOnEsc)
                Picker("⌘W를 누르면", selection: $model.config.cmdWAction) {
                    ForEach(CmdWAction.allCases) { Text($0.title).tag($0) }
                }
                Text("탭 닫기로 두면 마지막 남은 탭에서는 창이 닫힙니다. ⌘⇧T로 닫은 탭을 다시 열 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("메뉴바 아이콘을 클릭해도 열고 닫을 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("창 안에서 쓰는 단축키") {
                LabeledContent("⌘1 ~ ⌘9", value: "해당 번호 페이지로")
                LabeledContent("⌃Tab / ⌃⇧Tab", value: "다음 / 이전 페이지")
                LabeledContent("⌘L", value: "주소창으로 이동")
                LabeledContent("⌘R", value: "새로고침")
                LabeledContent("⌘[ / ⌘]", value: "뒤로 / 앞으로")
                LabeledContent("⌘T", value: "새 탭")
                LabeledContent("⌘⇧N", value: "새 시크릿 탭")
                LabeledContent("⌘Y", value: "방문 기록")
                LabeledContent("⌘W / ⌘⇧T", value: "탭 닫기 / 닫은 탭 다시 열기")
                LabeledContent("⌘F / ⌘G", value: "페이지에서 찾기 / 다음 찾기")
                LabeledContent("⌘+ / ⌘- / ⌘0", value: "확대 / 축소 / 원래 크기")
                LabeledContent("⌘⇧M", value: "현재 탭 음소거")
                LabeledContent("⌘⇧P", value: "영상 PIP (화면 속 화면)")
                LabeledContent("⌘,", value: "설정 열기")
            }
        }
        .formStyle(.grouped)
    }

    // 창
    var windowTab: some View {
        Form {
            Section("위치와 크기") {
                Picker("열리는 위치", selection: $model.config.position) {
                    ForEach(WindowPosition.allCases) { Text($0.title).tag($0) }
                }
                Stepper("너비: \(Int(model.config.width))", value: $model.config.width, in: 300...2400, step: 20)
                Stepper("높이: \(Int(model.config.height))", value: $model.config.height, in: 300...1600, step: 20)
                Text("창 가장자리를 끌면 크기, 위쪽 막대를 끌면 위치를 바꿀 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("표시") {
                Toggle("페이지 탭 막대 표시", isOn: $model.config.showTabBar)
                Toggle("탭에 페이지 이름 표시 (끄면 번호만 보임)", isOn: $model.config.showTabNames)
                    .disabled(!model.config.showTabBar)
                Toggle("주소창 표시", isOn: $model.config.showAddressBar)
                Picker("주소창 위치", selection: $model.config.addressBarAtBottom) {
                    Text("위 (탭 아래)").tag(false)
                    Text("아래 (창 맨 아래)").tag(true)
                }
                .disabled(!model.config.showAddressBar)
                Toggle("가운데 알림 표시 (확대 비율, 음소거, 다운로드 등)", isOn: $model.config.showHUD)
                Toggle("항상 다른 창 위에 표시", isOn: $model.config.alwaysOnTop)
                Toggle("모든 데스크탑(Spaces)에서 표시", isOn: $model.config.allSpaces)
                LabeledContent {
                    Slider(value: $model.config.opacity, in: 0.3...1.0).frame(width: 220)
                } label: {
                    Text(verbatim: "창 투명도 \(Int((model.config.opacity * 100).rounded()))%")
                }
            }
        }
        .formStyle(.grouped)
    }

    // 페이지
    // 새 탭 바로가기
    var quickLinksTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("+ 버튼(⌘T)으로 새 탭을 열면 보이는 시작 페이지의 바로가기예요.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($model.config.quickLinks) { $link in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        TextField("이름", text: $link.name).frame(width: 130)
                        TextField("https://", text: $link.url)
                        Button {
                            model.config.quickLinks.removeAll { $0.id == link.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in model.config.quickLinks.move(fromOffsets: from, toOffset: to) }
            }
            HStack {
                Button {
                    model.config.quickLinks.append(QuickLink(name: "새 바로가기", url: "https://"))
                } label: {
                    Label("바로가기 추가", systemImage: "plus")
                }
                Spacer()
                Button("기본 목록으로 되돌리기") { model.config.quickLinks = AppConfig.defaultQuickLinks }
            }
        }
    }

    var pagesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach($model.config.pages) { $page in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        TextField("이름", text: Binding(
                            get: { $page.wrappedValue.name },
                            set: { $page.wrappedValue.name = $0; $page.wrappedValue.autoName = false }
                        )).frame(width: 100)
                        TextField("https://", text: $page.url)
                        Picker("", selection: $page.device) {
                            ForEach(DeviceMode.allCases) { Text($0.short).tag($0) }
                        }
                        .labelsHidden().frame(width: 92).help("화면 종류")
                        Picker("", selection: $page.refreshMinutes) {
                            ForEach(refreshChoices, id: \.self) { m in
                                Text(m == 0 ? "새로고침 끔" : "\(m)분마다").tag(m)
                            }
                        }
                        .labelsHidden().frame(width: 104).help("자동 새로고침")
                        Button {
                            model.removePage(page.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("삭제")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    model.config.pages.move(fromOffsets: from, toOffset: to)
                }
            }
            HStack {
                Button {
                    model.addPage()
                } label: {
                    Label("페이지 추가", systemImage: "plus")
                }
                Spacer()
                Text("끌어서 순서 변경 · 주소 변경은 창을 다시 열 때 반영")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 패널 부품

// MARK: - 업데이트 (GitHub Releases의 "latest" 빌드)

final class Updater {
    let repo = "hyubbb/MenuCycle"
    weak var model: SettingsModel?
    var onAvailabilityChanged: ((Bool) -> Void)?
    private var zipURL: URL?

    var currentSHA: String { Bundle.main.object(forInfoDictionaryKey: "MCBuildCommit") as? String ?? "" }

    private func get(_ path: String, _ done: @escaping ([String: Any]?) -> Void) {
        guard let u = URL(string: "https://api.github.com/repos/\(repo)/\(path)") else { done(nil); return }
        var req = URLRequest(url: u)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done(nil); return }
            done(obj)
        }.resume()
    }

    private func setStatus(_ text: String, available: Bool? = nil, busy: Bool = false, notes: [String]? = nil) {
        DispatchQueue.main.async {
            guard let m = self.model else { return }
            m.updateStatus = text
            m.updateBusy = busy
            if let notes { m.updateNotes = notes }
            if let available {
                m.updateAvailable = available
                self.onAvailabilityChanged?(available)
            }
        }
    }

    /// manual: 설정에서 버튼을 눌렀을 때 (최신이어도 결과를 보여줌)
    func check(manual: Bool) {
        if manual { setStatus("확인 중…", busy: true) }
        get("releases/tags/latest") { [weak self] rel in
            guard let self else { return }
            guard let rel, let latestSHA = rel["target_commitish"] as? String else {
                if manual { self.setStatus("확인하지 못했어요. 인터넷 연결을 확인하거나 잠시 후 다시 시도해 주세요.") }
                return
            }
            let assets = rel["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String) == "MenuCycle-app.zip" }
            self.zipURL = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:))
            let name = (rel["name"] as? String) ?? "최신 빌드"
            let cur = self.currentSHA

            if !cur.isEmpty && latestSHA.hasPrefix(cur) || cur.hasPrefix(latestSHA) && !cur.isEmpty {
                self.setStatus(manual ? "최신 버전을 쓰고 있어요." : "", available: false)
                return
            }
            guard self.zipURL != nil else {
                if manual { self.setStatus("새 빌드를 준비 중이에요. 몇 분 뒤에 다시 확인해 주세요.") }
                return
            }
            guard cur.count >= 7 else {
                // 직접 빌드해서 기준 커밋을 모르는 경우
                self.setStatus("새 버전: \(name)", available: true, notes: [])
                return
            }
            // 지금 버전과 최신 버전 사이의 변경 내역
            self.get("compare/\(cur)...\(latestSHA)") { cmp in
                let status = cmp?["status"] as? String
                if status == "behind" || status == "identical" {
                    self.setStatus(manual ? "최신 버전을 쓰고 있어요." : "", available: false)
                    return
                }
                let commits = cmp?["commits"] as? [[String: Any]] ?? []
                let notes = commits.reversed().compactMap { c -> String? in
                    let msg = (c["commit"] as? [String: Any])?["message"] as? String
                    return msg?.components(separatedBy: "\n").first
                }
                self.setStatus("새 버전이 있어요: \(name)", available: true, notes: notes)
            }
        }
    }

    /// zip을 받아 풀고, 앱이 꺼지면 교체 후 다시 실행하는 작은 스크립트를 띄운 뒤 앱을 종료
    func install() {
        guard let zipURL else { check(manual: true); return }
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            setStatus("\(dest.deletingLastPathComponent().path) 폴더에 쓸 권한이 없어요. 릴리스 페이지에서 DMG로 설치해 주세요.")
            return
        }
        setStatus("내려받는 중…", busy: true)
        URLSession.shared.downloadTask(with: zipURL) { [weak self] tmp, resp, _ in
            guard let self else { return }
            guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                self.setStatus("내려받지 못했어요. 잠시 후 다시 시도해 주세요.")
                return
            }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("MenuCycleUpdate-\(UUID().uuidString)")
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zipPath = work.appendingPathComponent("app.zip")
            do { try fm.moveItem(at: tmp, to: zipPath) } catch {
                self.setStatus("파일을 저장하지 못했어요.")
                return
            }
            self.setStatus("설치 준비 중…", busy: true)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zipPath.path, work.path]
            do { try unzip.run(); unzip.waitUntilExit() } catch {}
            let newApp = work.appendingPathComponent("MenuCycle.app")
            guard unzip.terminationStatus == 0,
                  Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                self.setStatus("받은 파일이 올바르지 않아요. 릴리스 페이지에서 DMG로 설치해 주세요.")
                return
            }
            // 앱이 완전히 꺼질 때까지 기다렸다가 교체하고 다시 실행
            let script = work.appendingPathComponent("swap.sh")
            let body = """
            #!/bin/bash
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$3" && mv "$2" "$3" && xattr -cr "$3"
            open "$3"
            """
            do { try body.write(to: script, atomically: true, encoding: .utf8) } catch {
                self.setStatus("설치 스크립트를 만들지 못했어요.")
                return
            }
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/bash")
            swap.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, dest.path]
            do { try swap.run() } catch {
                self.setStatus("설치를 시작하지 못했어요.")
                return
            }
            self.setStatus("다시 시작하는 중…", busy: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }.resume()
    }
}

// MARK: - 방문 기록

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: String
    var title: String
    var date: Date
}

/// "https://www.youtube.com/watch" → "youtube.com/watch"
func strippedURL(_ s: String) -> String {
    var t = s
    for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
    if t.lowercased().hasPrefix("www.") { t.removeFirst(4) }
    return t
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = [] // 최신이 앞
    private var saveWork: DispatchWorkItem?
    let limit = 5000

    static var fileURL: URL {
        ConfigStore.url.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    init() {
        if let d = try? Data(contentsOf: HistoryStore.fileURL),
           let e = try? JSONDecoder().decode([HistoryEntry].self, from: d) {
            entries = e
        }
    }

    func record(url: URL, title: String?) {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        let s = url.absoluteString
        let t = title ?? ""
        if let first = entries.first, first.url == s {
            if !t.isEmpty { entries[0].title = t }
            entries[0].date = Date()
        } else {
            entries.insert(HistoryEntry(url: s, title: t, date: Date()), at: 0)
            if entries.count > limit { entries.removeLast(entries.count - limit) }
        }
        scheduleSave()
    }

    /// 페이지 제목은 주소보다 늦게 정해지므로 최근 기록에서 찾아 채움
    func updateTitle(url: String, title: String) {
        guard !title.isEmpty, let i = entries.prefix(20).firstIndex(where: { $0.url == url }),
              entries[i].title != title else { return }
        entries[i].title = title
        scheduleSave()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        scheduleSave()
    }

    /// since == nil 이면 전체 삭제
    func clear(since: Date?) {
        if let since { entries.removeAll { $0.date >= since } } else { entries.removeAll() }
        scheduleSave()
    }

    /// 주소창 자동완성: 입력한 글자로 시작하는 사이트 중 가장 많이 간 곳
    func complete(_ typed: String) -> String? {
        let q = typed.lowercased()
        guard !q.isEmpty, !q.hasPrefix("http") else { return nil }
        var hosts: [String: Int] = [:]
        var urls: [String: Int] = [:]
        for e in entries {
            let full = strippedURL(e.url)
            urls[full, default: 0] += 1
            if let u = URL(string: e.url), var h = u.host?.lowercased() {
                if h.hasPrefix("www.") { h.removeFirst(4) }
                hosts[h, default: 0] += 1
            }
        }
        if let h = hosts.filter({ $0.key.hasPrefix(q) }).max(by: { $0.value < $1.value })?.key, h.count > q.count {
            return h
        }
        let best = urls.filter { $0.key.lowercased().hasPrefix(q) && $0.key.count > q.count }
            .max { a, b in a.value == b.value ? a.key.count > b.key.count : a.value < b.value }
        return best?.key
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = entries
        let w = DispatchWorkItem {
            if let d = try? JSONEncoder().encode(snapshot) {
                try? d.write(to: HistoryStore.fileURL, options: .atomic)
            }
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }
}

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    var onOpen: (String, Bool) -> Void // (주소, 새 탭 여부)
    @State private var query = ""
    @State private var confirmClear = false

    var filtered: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? store.entries
            : store.entries.filter { $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        return Array(list.prefix(500))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("기록 검색 (제목 또는 주소)", text: $query)
                    .textFieldStyle(.roundedBorder)
                Menu("기록 지우기") {
                    Button("지난 1시간") { store.clear(since: Date().addingTimeInterval(-3600)) }
                    Button("오늘") { store.clear(since: Calendar.current.startOfDay(for: Date())) }
                    Divider()
                    Button("전체…") { confirmClear = true }
                }
                .fixedSize()
            }
            if filtered.isEmpty {
                Spacer()
                Text(query.isEmpty ? "방문 기록이 없어요" : "검색 결과가 없어요").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { e in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title.isEmpty ? strippedURL(e.url) : e.title).lineLimit(1)
                            Text(strippedURL(e.url)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(e.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpen(e.url, false) }
                    .contextMenu {
                        Button("현재 탭에서 열기") { onOpen(e.url, false) }
                        Button("새 탭에서 열기") { onOpen(e.url, true) }
                        Button("주소 복사") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(e.url, forType: .string)
                        }
                        Divider()
                        Button("기록에서 삭제") { store.remove(e.id) }
                    }
                }
            }
            Text("두 번 클릭: 현재 탭에서 열기 · 우클릭: 새 탭에서 열기, 삭제")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 440)
        .alert("방문 기록을 모두 지울까요?", isPresented: $confirmClear) {
            Button("모두 지우기", role: .destructive) { store.clear(since: nil) }
            Button("취소", role: .cancel) {}
        }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class HUDView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 10
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 15)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func flash(_ text: String, in parent: NSView) {
        label.stringValue = text
        label.sizeToFit()
        let h: CGFloat = 42
        let w = min(label.frame.width + 36, parent.bounds.width - 40)
        frame = NSRect(x: (parent.bounds.width - w) / 2, y: (parent.bounds.height - h) / 2,
                       width: w, height: h)
        label.frame = NSRect(x: 18, y: (h - label.frame.height) / 2,
                             width: w - 36, height: label.frame.height)
        removeFromSuperview()
        parent.addSubview(self)
        alphaValue = 1
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self?.animator().alphaValue = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}

/// 클릭하면 페이지 선택, 좌우로 끌면 순서 변경
final class TabButton: NSButton {
    weak var owner: AppDelegate?

    override func mouseDown(with event: NSEvent) {
        let start = event.locationInWindow
        var dragging = false
        while let e = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                      until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if e.type == .leftMouseUp {
                if dragging { owner?.tabDragEnded(self) } else { owner?.tabClicked(self) }
                return
            }
            if !dragging && abs(e.locationInWindow.x - start.x) > 5 {
                dragging = true
                owner?.tabDragBegan(self)
            }
            if dragging { owner?.tabDragMoved(self, windowPoint: e.locationInWindow) }
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
}

/// 웹뷰를 만들 때 쓴 값. 설정이 이것과 달라지면 웹뷰를 새로 만듦
struct WebMeta {
    var url: String
    var ua: String
}

/// 탭 음소거: 영상·소리 요소를 음소거하고, 나중에 재생되는 것도 음소거.
/// 사이트가 원래 음소거해 둔 영상은 건드리지 않도록 우리가 음소거한 것만 표시해 둠
func muteScript(_ on: Bool) -> WKUserScript {
    let src = """
    (function(){
      if(!window.__mcMute){
        window.__mcMute={on:false};
        var mute=function(m){ if(!m.muted){ m.muted=true; m.setAttribute('data-mc-muted','1'); } };
        document.addEventListener('play',function(e){ if(window.__mcMute.on&&e.target&&e.target.tagName){ mute(e.target); } },true);
        window.__mcSetMuted=function(v){
          window.__mcMute.on=v;
          document.querySelectorAll('video,audio').forEach(function(m){
            if(v){ mute(m); }
            else if(m.getAttribute('data-mc-muted')){ m.muted=false; m.removeAttribute('data-mc-muted'); }
          });
        };
      }
      if(\(on ? "true" : "false")){ window.__mcSetMuted(true); }
    })();
    """
    return WKUserScript(source: src, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
}

/// 메뉴바 아이콘: 창 테두리 안 위쪽에 탭 3개 (Resources/MenuBarIcon.svg 와 같은 모양).
/// 템플릿 이미지라 라이트/다크 메뉴바에 맞게 자동으로 색이 바뀜. badge: 새 버전 있음 표시 점
func menuBarIcon(badge: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let black = NSColor.black
        black.setStroke()
        let frame = NSBezierPath(roundedRect: NSRect(x: 1.8, y: 2.6, width: 14.4, height: 12.8), xRadius: 2.6, yRadius: 2.6)
        frame.lineWidth = 1.5
        frame.stroke()
        black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 3.9, y: 4.6, width: 3, height: 2.3), xRadius: 0.7, yRadius: 0.7).fill()
        black.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: NSRect(x: 7.5, y: 4.6, width: 3, height: 2.3), xRadius: 0.7, yRadius: 0.7).fill()
        NSBezierPath(roundedRect: NSRect(x: 11.1, y: 4.6, width: 3, height: 2.3), xRadius: 0.7, yRadius: 0.7).fill()
        black.setFill()
        NSRect(x: 1.8, y: 7.4, width: 14.4, height: 1.2).fill()
        if badge {
            // 오른쪽 위 모서리를 지우고 점 찍기
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 10.5, y: 0, width: 7.5, height: 7.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12, y: 1.5, width: 4.5, height: 4.5)).fill()
        }
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "MenuCycle"
    return img
}

// MARK: - 새 탭 시작 페이지 (menucycle://newtab)

final class StartPageHandler: NSObject, WKURLSchemeHandler {
    var html: () -> String = { "" }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let data = Data(html().utf8)
        let url = task.request.url ?? URL(string: startPageURL)!
        task.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count,
                                    textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
let startPageHandler = StartPageHandler()

func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

/// 잘 알려진 사이트는 브랜드 색 아이콘, 나머지는 첫 글자 아이콘
func quickLinkIcon(_ link: QuickLink) -> String {
    let host = (URL(string: link.url.contains("://") ? link.url : "https://" + link.url)?.host ?? "").lowercased()
    func box(_ bg: String, _ inner: String) -> String {
        "<svg viewBox='0 0 64 64'><rect width='64' height='64' rx='16' fill='\(bg)'/>\(inner)</svg>"
    }
    if host.contains("music.youtube") {
        return box("#ff0033", "<circle cx='32' cy='32' r='17' fill='none' stroke='#fff' stroke-width='3.5'/><path d='M28 24.5v15l12-7.5z' fill='#fff'/>")
    }
    if host.contains("youtube") {
        return box("#ff0033", "<rect x='13' y='19' width='38' height='26' rx='8' fill='#fff'/><path d='M28 25.5v13l11-6.5z' fill='#ff0033'/>")
    }
    if host.contains("naver") {
        return box("#03c75a", "<path d='M19 18h9.5l7.5 11.5V18H45v28h-9.5L28 34.5V46H19z' fill='#fff'/>")
    }
    if host.contains("gemini") {
        return box("#ffffff", "<defs><linearGradient id='gm' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#4285f4'/><stop offset='1' stop-color='#a142f4'/></linearGradient></defs><path d='M32 10c1.6 11.4 10.6 20.4 22 22-11.4 1.6-20.4 10.6-22 22-1.6-11.4-10.6-20.4-22-22 11.4-1.6 20.4-10.6 22-22z' fill='url(#gm)'/>")
    }
    if host.contains("google") {
        return box("#ffffff", "<text x='32' y='44' text-anchor='middle' font-family='-apple-system,Helvetica,Arial' font-weight='700' font-size='34' fill='#4285f4'>G</text>")
    }
    if host.contains("instagram") {
        return "<svg viewBox='0 0 64 64'><defs><linearGradient id='ig' x1='0' y1='1' x2='1' y2='0'><stop offset='0' stop-color='#feda75'/><stop offset='.35' stop-color='#fa7e1e'/><stop offset='.65' stop-color='#d62976'/><stop offset='1' stop-color='#4f5bd5'/></linearGradient></defs><rect width='64' height='64' rx='16' fill='url(#ig)'/><rect x='16' y='16' width='32' height='32' rx='10' fill='none' stroke='#fff' stroke-width='3.5'/><circle cx='32' cy='32' r='7.5' fill='none' stroke='#fff' stroke-width='3.5'/><circle cx='41.5' cy='22.5' r='2.2' fill='#fff'/></svg>"
    }
    if host.contains("spotify") {
        return box("#1db954", "<path d='M18 25c9-3 20-2.5 28 2M20 32.5c7.5-2.3 16.5-1.8 23 1.8M22 39.5c6-1.7 12.5-1.3 18 1.4' fill='none' stroke='#000' stroke-width='3.6' stroke-linecap='round'/>")
    }
    if host.contains("chatgpt") || host.contains("openai") {
        return box("#000000", "<text x='32' y='40' text-anchor='middle' font-family='-apple-system,Helvetica,Arial' font-weight='700' font-size='20' fill='#fff'>GPT</text>")
    }
    if host.contains("claude") {
        return box("#d97757", "<g stroke='#fff' stroke-width='4' stroke-linecap='round'><path d='M32 16v32M16 32h32M20.7 20.7l22.6 22.6M43.3 20.7L20.7 43.3'/></g>")
    }
    let letter = htmlEscape(String(link.name.prefix(1)).uppercased())
    let colors = ["#5b8def", "#e5677d", "#f0a63c", "#4fb98a", "#9a6cf0", "#38a9c9"]
    let seed = host.unicodeScalars.reduce(0) { $0 + Int($1.value) } // 실행할 때마다 색이 바뀌지 않게
    let bg = colors[seed % colors.count]
    return box(bg, "<text x='32' y='42' text-anchor='middle' font-family='-apple-system,Helvetica,Arial' font-weight='700' font-size='28' fill='#fff'>\(letter)</text>")
}

func startPageHTML(links: [QuickLink], engine: SearchEngine) -> String {
    let tiles = links.map { l -> String in
        let href = l.url.contains("://") ? l.url : "https://" + l.url
        return "<a class='tile' href='\(htmlEscape(href))'><div class='ic'>\(quickLinkIcon(l))</div><div class='nm'>\(htmlEscape(l.name))</div></a>"
    }.joined()
    let tpl = engine.searchURL("__Q__")?.absoluteString ?? "https://www.google.com/search?q=__Q__"
    return """
    <!doctype html><html lang="ko"><head><meta charset="utf-8"><title>새 탭</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
    :root{--bg:#f5f5f7;--fg:#1d1d1f;--sub:#6e6e73;--card:#ffffff;--line:#d2d2d7}
    @media (prefers-color-scheme:dark){:root{--bg:#1c1c1e;--fg:#f5f5f7;--sub:#a1a1a6;--card:#2c2c2e;--line:#3a3a3c}}
    *{box-sizing:border-box}
    body{margin:0;min-height:100vh;background:var(--bg);color:var(--fg);font-family:-apple-system,"Apple SD Gothic Neo",sans-serif;
         display:flex;flex-direction:column;align-items:center;padding:12vh 20px 40px}
    form{width:100%;max-width:520px;margin-bottom:36px}
    input{width:100%;height:46px;border-radius:23px;border:1px solid var(--line);background:var(--card);color:var(--fg);
          padding:0 20px;font-size:15px;outline:none}
    input:focus{border-color:#0a84ff;box-shadow:0 0 0 3px rgba(10,132,255,.25)}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(84px,1fr));gap:18px 10px;width:100%;max-width:560px}
    .tile{display:flex;flex-direction:column;align-items:center;gap:8px;text-decoration:none;color:var(--fg);padding:8px 4px;border-radius:14px}
    .tile:hover{background:rgba(127,127,127,.12)}
    .ic{width:52px;height:52px;border-radius:14px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.15)}
    .ic svg{width:100%;height:100%;display:block}
    .nm{font-size:12px;color:var(--sub);max-width:84px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .empty{color:var(--sub);font-size:13px}
    </style></head><body>
    <form id="f"><input id="q" placeholder="검색어 또는 주소 입력" autocomplete="off"></form>
    <div class="grid">\(tiles.isEmpty ? "<div class='empty'>설정 → 새 탭에서 바로가기를 추가하세요</div>" : tiles)</div>
    <script>
    document.getElementById('f').addEventListener('submit', function(e){
      e.preventDefault();
      var q = document.getElementById('q').value.trim();
      if (!q) return;
      if (/^[a-z]+:\\/\\//i.test(q)) { location.href = q; return; }
      if (q.indexOf(' ') < 0 && q.indexOf('.') > 0) { location.href = 'https://' + q; return; }
      location.href = \(jsString(tpl)).replace('__Q__', encodeURIComponent(q));
    });
    </script></body></html>
    """
}

func jsString(_ s: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [s])
    let arr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
    return String(arr.dropFirst().dropLast()) // ["..."] → "..."
}

/// 우클릭한 위치의 링크 주소를 앱에 알려줌 (우클릭 메뉴에 '기본 브라우저에서 열기'를 넣기 위해)
let contextLinkScript = WKUserScript(source: """
document.addEventListener('contextmenu', function(e){
  var a = (e.target && e.target.closest) ? e.target.closest('a[href]') : null;
  try { window.webkit.messageHandlers.mcContextLink.postMessage(a ? a.href : ''); } catch (_) {}
}, true);
""", injectionTime: .atDocumentStart, forMainFrameOnly: false)

final class ContextLinkHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let wv = message.webView as? MCWebView else { return }
        let s = message.body as? String ?? ""
        wv.contextLink = s.isEmpty ? nil : URL(string: s)
    }
}
let contextLinkHandler = ContextLinkHandler()

/// 링크 우클릭 메뉴에 '기본 브라우저에서 열기' 추가, '새 윈도우에서 열기'는 '새 탭에서 열기'로 이름 변경
final class MCWebView: WKWebView {
    var contextLink: URL?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let link = contextLink, link.scheme == "http" || link.scheme == "https" else { return }
        guard let i = menu.items.firstIndex(where: {
            ($0.identifier?.rawValue ?? "") == "WKMenuItemIdentifierOpenLinkInNewWindow"
        }) else { return }
        let openItem = menu.items[i]
        openItem.title = "새 탭에서 링크 열기"
        let item = NSMenuItem(title: "기본 브라우저에서 열기", action: #selector(openInDefaultBrowser(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = link
        menu.insertItem(item, at: i + 1)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        contextLink = nil
    }

    @objc func openInDefaultBrowser(_ sender: NSMenuItem) {
        if let u = sender.representedObject as? URL { NSWorkspace.shared.open(u) }
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKUIDelegate,
                         WKNavigationDelegate, WKDownloadDelegate, NSTextFieldDelegate {
    let model = SettingsModel(config: ConfigStore.load())
    var config: AppConfig { model.config }
    var applied = AppConfig()
    var isApplying = false
    var saveWork: DispatchWorkItem?

    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    var bg: NSVisualEffectView!
    let tabBar = NSView()
    let tabStack = NSStackView()
    let addressBar = NSView()
    let urlField = NSTextField()
    var backButton: NSButton!
    var forwardButton: NSButton!
    var deviceButton: NSButton!
    var muteButton: NSButton!
    var moreButton: NSButton!
    var opacityButton: NSButton!
    let opacityPopover = NSPopover()
    let opacitySlider = NSSlider()
    let opacityLabel = NSTextField(labelWithString: "")
    var plusButton: NSButton!
    let findBar = NSVisualEffectView()
    let findField = NSSearchField()
    var container: NSView!
    let hud = HUDView()
    let emptyLabel = NSTextField(labelWithString: "설정 → 페이지에서 사이트를 추가하세요")
    var settingsWindow: NSWindow?

    var webViews: [UUID: WKWebView] = [:]
    var webMeta: [UUID: WebMeta] = [:]
    var observers: [UUID: [NSKeyValueObservation]] = [:]
    var currentID: UUID?

    var favicons: [UUID: NSImage] = [:]
    var faviconHost: [UUID: String] = [:]
    var lastViewed: [UUID: Date] = [:]
    var lastRefresh: [UUID: Date] = [:]
    var resumeURL: [UUID: URL] = [:]      // 메모리에서 내린 탭이 다시 열릴 주소
    var needsNudge: Set<UUID> = []        // 숨겨진 상태에서 로딩이 끝나 레이아웃을 다시 잡아야 하는 탭
    var downloadDest: [ObjectIdentifier: URL] = [:]
    var maintenanceTimer: Timer?
    var closedTabs: [(page: PageConfig, index: Int)] = []
    let history = HistoryStore()
    let updater = Updater()
    var updateTimer: Timer?
    var historyWindow: NSWindow?
    var lastRecorded: [UUID: String] = [:]
    var lastTypedLength = 0
    var popupOpener: [UUID: UUID?] = [:] // 팝업 탭 → 그 팝업을 연 원래 탭

    var hotkeys: [HotKey] = []
    var hotkeysSuspended = false

    let tabH: CGFloat = 32
    let addrH: CGFloat = 32

    // MARK: 시작

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 예전 기본 페이지 3개(Claude·번역·YouTube) 그대로면 Google 하나로 교체
        let oldDefaults: Set<String> = ["https://claude.ai", "https://papago.naver.com", "https://m.youtube.com"]
        if model.config.pages.count == 3 && Set(model.config.pages.map { $0.url }) == oldDefaults {
            model.config.pages = [AppConfig.googlePage()]
        }
        applied = config
        ConfigStore.save(config) // 예전 형식 파일을 새 형식으로 정리

        model.onChange = { [weak self] in self?.apply() }
        model.openConfigFile = { NSWorkspace.shared.open(ConfigStore.url) }
        model.openHistory = { [weak self] in self?.openHistoryWindow() }
        startPageHandler.html = { [weak self] in
            guard let self else { return "" }
            return startPageHTML(links: self.config.quickLinks, engine: self.config.searchEngine)
        }
        updater.model = model
        updater.onAvailabilityChanged = { [weak self] available in
            // 새 버전이 있으면 메뉴바 아이콘에 표시
            self?.statusItem.button?.image = menuBarIcon(badge: available)
        }
        model.checkUpdate = { [weak self] in self?.updater.check(manual: true) }
        model.installUpdate = { [weak self] in self?.updater.install() }
        if config.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.updater.check(manual: false) }
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            guard let self, self.config.autoCheckUpdates else { return }
            self.updater.check(manual: false)
        }
        model.reloadConfigFile = { [weak self] in self?.model.config = ConfigStore.load() }
        HotkeyRecorderView.onRecordingChanged = { [weak self] rec in
            self?.hotkeysSuspended = rec
            self?.registerHotkeys()
        }

        setupMainMenu()
        setupStatusItem()
        setupPanel()
        setupFindBar()
        applyWindowBehavior()
        layoutChrome()
        registerHotkeys()
        installKeyMonitor()
        panel.alphaValue = CGFloat(config.opacity)
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.maintenance()
        }

        if let s = UserDefaults.standard.string(forKey: "lastPageID"), let id = UUID(uuidString: s),
           config.pages.contains(where: { $0.id == id }) {
            currentID = id
        } else {
            currentID = config.pages.first?.id
        }
        rebuildTabs()
        select(currentIndex, showHUD: false)
    }

    func applicationDidResignActive(_ notification: Notification) {
        if config.closeOnBlur && panel.isVisible { panel.orderOut(nil) }
    }

    func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "MenuCycle 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // 액세서리 앱도 Edit 메뉴가 있어야 ⌘C/⌘V가 동작함
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = menuBarIcon(badge: false)
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let b = NSButton(image: img, target: self, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.toolTip = tip
        return b
    }

    func setupPanel() {
        let w = CGFloat(config.width), h = CGFloat(config.height)
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                              styleMask: [.borderless, .resizable],
                              backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 300, height: 300)
        panel.delegate = self

        bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        panel.contentView = bg

        // 탭 막대
        tabBar.autoresizingMask = [.width, .minYMargin]
        tabStack.orientation = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 4
        tabStack.autoresizingMask = [.width, .height]
        tabBar.addSubview(tabStack)
        plusButton = iconButton("plus", "새 탭 (⌘T)", #selector(newTab))
        plusButton.autoresizingMask = [.minXMargin]
        tabBar.addSubview(plusButton)
        bg.addSubview(tabBar)

        // 주소창 막대
        addressBar.autoresizingMask = [.width, .minYMargin]
        backButton = iconButton("chevron.left", "뒤로 (⌘[)", #selector(goBack))
        forwardButton = iconButton("chevron.right", "앞으로 (⌘])", #selector(goForward))
        let reload = iconButton("arrow.clockwise", "새로고침 (⌘R)", #selector(reloadCurrent))
        let home = iconButton("house", "홈 (등록한 주소 / 새 탭은 검색 엔진 첫 화면)", #selector(goHome))
        let gear = iconButton("gearshape", "설정 (⌘,)", #selector(openSettings))

        let bw: CGFloat = 24, y: CGFloat = 4, bh: CGFloat = 24
        backButton.frame = NSRect(x: 8, y: y, width: bw, height: bh)
        forwardButton.frame = NSRect(x: 32, y: y, width: bw, height: bh)
        reload.frame = NSRect(x: 56, y: y, width: bw, height: bh)
        home.frame = NSRect(x: 80, y: y, width: bw, height: bh)
        moreButton = iconButton("ellipsis.circle", "더 보기 (PIP · 확대 · 찾기 · 자동 새로고침 · 다운로드)", #selector(showMoreMenu(_:)))
        deviceButton = iconButton("desktopcomputer", "화면 종류 (PC / iPhone / iPad / Android)", #selector(showDeviceMenu(_:)))
        muteButton = iconButton("speaker.wave.2", "음소거 (⌘⇧M)", #selector(toggleMute))
        opacityButton = iconButton("circle.lefthalf.filled", "창 투명도", #selector(showOpacity(_:)))
        setupOpacityPopover()
        let rightButtons: [NSView] = [muteButton, deviceButton, opacityButton, moreButton, gear]
        for (k, b) in rightButtons.enumerated() {
            b.frame = NSRect(x: w - 34 - CGFloat(rightButtons.count - 1 - k) * 26, y: y, width: bw, height: bh)
            b.autoresizingMask = [.minXMargin]
        }

        urlField.frame = NSRect(x: 110, y: 5, width: w - 110 - 8 - CGFloat(rightButtons.count) * 26, height: 22)
        urlField.autoresizingMask = [.width]
        urlField.bezelStyle = .roundedBezel
        urlField.font = .systemFont(ofSize: 12)
        urlField.placeholderString = "주소 또는 검색어 입력 (⌘L)"
        urlField.delegate = self // 방문 기록 자동완성
        urlField.lineBreakMode = .byTruncatingTail
        urlField.cell?.sendsActionOnEndEditing = false
        urlField.target = self
        urlField.action = #selector(urlEntered(_:))

        addressBar.frame = NSRect(x: 0, y: 0, width: w, height: addrH)
        tabBar.frame = NSRect(x: 0, y: 0, width: w, height: tabH)
        layoutTabBarContents()
        let barViews: [NSView] = [backButton, forwardButton, reload, home, urlField] + rightButtons
        barViews.forEach { addressBar.addSubview($0) }
        bg.addSubview(addressBar)

        container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.autoresizingMask = [.width, .height]
        bg.addSubview(container)

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.frame = NSRect(x: 0, y: container.bounds.midY - 10, width: w, height: 20)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        container.addSubview(emptyLabel)
    }

    /// 탭 막대 / 주소창 표시 여부에 따라 배치
    func layoutChrome() {
        let b = bg.bounds
        var top = b.height
        tabBar.isHidden = !config.showTabBar
        if config.showTabBar {
            top -= tabH
            tabBar.frame = NSRect(x: 0, y: top, width: b.width, height: tabH)
            layoutTabBarContents()
        }
        addressBar.isHidden = !config.showAddressBar
        var bottom: CGFloat = 0
        if config.showAddressBar {
            addressBar.setFrameSize(NSSize(width: b.width, height: addrH))
            if config.addressBarAtBottom {
                addressBar.setFrameOrigin(NSPoint(x: 0, y: 0))
                addressBar.autoresizingMask = [.width, .maxYMargin] // 아래에 붙어 있음
                bottom = addrH
            } else {
                top -= addrH
                addressBar.setFrameOrigin(NSPoint(x: 0, y: top))
                addressBar.autoresizingMask = [.width, .minYMargin] // 위에 붙어 있음
            }
        }
        container.frame = NSRect(x: 0, y: bottom, width: b.width, height: max(0, top - bottom))
    }

    /// 탭들은 왼쪽부터 채우고 오른쪽 끝에 + 버튼
    func layoutTabBarContents() {
        let b = tabBar.bounds
        tabStack.frame = NSRect(x: 8, y: 5, width: max(0, b.width - 8 - 36), height: max(0, b.height - 10))
        plusButton.frame = NSRect(x: b.width - 32, y: (b.height - 24) / 2, width: 24, height: 24)
    }

    func applyWindowBehavior() {
        panel.level = config.alwaysOnTop ? .floating : .normal
        settingsWindow?.level = panel.level // 설정 창이 패널 뒤로 숨지 않게
        panel.collectionBehavior = config.allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    // MARK: 설정 반영

    func apply() {
        let old = applied
        let new = config
        applied = new
        isApplying = true
        defer { isApplying = false }

        scheduleSave()

        if new.hotkeysDiffer(from: old) { registerHotkeys() }
        if new.alwaysOnTop != old.alwaysOnTop || new.allSpaces != old.allSpaces { applyWindowBehavior() }

        if abs(panel.frame.width - CGFloat(new.width)) > 1 || abs(panel.frame.height - CGFloat(new.height)) > 1 {
            var f = panel.frame
            let top = f.maxY
            f.size = NSSize(width: new.width, height: new.height)
            f.origin.y = top - f.height
            panel.setFrame(f, display: true)
        }

        if new.showTabBar != old.showTabBar || new.showAddressBar != old.showAddressBar
            || new.addressBarAtBottom != old.addressBarAtBottom { layoutChrome() }
        if new.showTabNames != old.showTabNames { rebuildTabs() }
        if new.quickLinks != old.quickLinks || new.searchEngine != old.searchEngine {
            // 열려 있는 시작 페이지를 새 목록으로 다시 그림
            for wv in webViews.values where wv.url?.scheme == "menucycle" { wv.reload() }
        }
        if new.opacity != old.opacity { panel.alphaValue = CGFloat(new.opacity) }

        if new.pages != old.pages {
            let ids = Set(new.pages.map { $0.id })
            for id in webViews.keys where !ids.contains(id) { dropWebView(id) }
            var currentGone = false
            if currentID == nil || !ids.contains(currentID!) {
                let oldIndex = old.pages.firstIndex { $0.id == currentID } ?? 0
                currentID = new.pages.isEmpty ? nil : new.pages[min(oldIndex, new.pages.count - 1)].id
                currentGone = true
            }
            rebuildTabs()
            if panel.isVisible && currentGone { select(currentIndex, showHUD: false) }
        }
    }

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            ConfigStore.save(self.config)
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveWork?.cancel()
        ConfigStore.save(config)
    }

    // MARK: 전역 단축키

    func registerHotkeys() {
        hotkeys.removeAll()
        guard !hotkeysSuspended else { return }
        var errors: [String] = []
        var used: [KeyCombo] = []

        func reg(_ c: KeyCombo?, _ id: UInt32, _ label: String, _ action: @escaping () -> Void) {
            guard let c else { return }
            if used.contains(c) {
                errors.append("\(label) \(c.display): 다른 동작과 키가 겹칩니다")
                return
            }
            used.append(c)
            let hk = HotKey(combo: c, id: id, handler: action)
            if hk.status != noErr {
                errors.append("\(label) \(c.display): 다른 앱이 이미 사용 중입니다")
            } else {
                hotkeys.append(hk)
            }
        }

        reg(config.openKey, 1, config.sameKeyToggle ? "열기/닫기" : "열기") { [weak self] in self?.openKeyPressed() }
        if !config.sameKeyToggle {
            reg(config.closeKey, 2, "닫기") { [weak self] in self?.hidePanel() }
        }
        reg(config.nextKey, 3, "다음 페이지") { [weak self] in self?.stepKeyPressed(1) }
        reg(config.prevKey, 4, "이전 페이지") { [weak self] in self?.stepKeyPressed(-1) }

        DispatchQueue.main.async { [weak self] in self?.model.hotkeyErrors = errors }
    }

    var panelIsFront: Bool { panel.isVisible && panel.isKeyWindow && NSApp.isActive }

    func openKeyPressed() {
        if !panel.isVisible {
            showPanel()
        } else if config.sameKeyToggle {
            if panelIsFront || config.alwaysOnTop { hidePanel() } else { showPanel() }
        } else if panelIsFront {
            if config.openKeyWhileOpenNext { select(currentIndex + 1, showHUD: true) }
        } else {
            showPanel()
        }
    }

    func stepKeyPressed(_ step: Int) {
        if panel.isVisible {
            if !panelIsFront { showPanel() }
            select(currentIndex + step, showHUD: true)
        } else {
            showPanel()
            select(currentIndex + step, showHUD: true)
        }
    }

    // MARK: 창 안 단축키

    func installKeyMonitor() {
        let digitCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                          kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let code = Int(e.keyCode)
            let editingURL = self.urlField.currentEditor() != nil

            if code == kVK_Escape && flags.isEmpty {
                if !self.findBar.isHidden { self.hideFind(); return nil }
                if editingURL {
                    self.updateAddressBar(force: true)
                    if let wv = self.currentWebView { self.panel.makeFirstResponder(wv) }
                    return nil
                }
                if self.config.closeOnEsc { self.hidePanel(); return nil }
                return e
            }

            if flags == .command {
                if let i = digitCodes.firstIndex(of: code) { self.select(i, showHUD: true); return nil }
                switch code {
                case kVK_ANSI_R: self.reloadCurrent(); return nil
                case kVK_ANSI_L: self.focusAddressBar(); return nil
                case kVK_ANSI_T: self.newTab(); return nil
                case kVK_ANSI_Y: self.openHistoryWindow(); return nil
                case kVK_ANSI_F: self.showFind(); return nil
                case kVK_ANSI_G: self.find(backwards: false); return nil
                case kVK_ANSI_Equal: self.zoomIn(); return nil
                case kVK_ANSI_Minus: self.zoomOut(); return nil
                case kVK_ANSI_0: self.zoomReset(); return nil
                case kVK_ANSI_LeftBracket: self.goBack(); return nil
                case kVK_ANSI_RightBracket: self.goForward(); return nil
                case kVK_ANSI_W:
                    switch self.config.cmdWAction {
                    case .closeTab: self.closeCurrentTab(); return nil
                    case .hideWindow: self.hidePanel(); return nil
                    case .nothing: break
                    }
                default: break
                }
            }
            if flags == [.command, .shift] {
                switch code {
                case kVK_ANSI_Equal: self.zoomIn(); return nil   // ⌘+ (한글 자판 포함)
                case kVK_ANSI_G: self.find(backwards: true); return nil
                case kVK_ANSI_M: self.toggleMute(); return nil
                case kVK_ANSI_P: self.togglePiP(); return nil
                case kVK_ANSI_T: self.reopenClosedTab(); return nil
                case kVK_ANSI_N: self.newIncognitoTab(); return nil
                default: break
                }
            }
            if code == kVK_Tab && flags == .control { self.select(self.currentIndex + 1, showHUD: true); return nil }
            if code == kVK_Tab && flags == [.control, .shift] { self.select(self.currentIndex - 1, showHUD: true); return nil }
            return e
        }
    }

    // MARK: 패널 표시

    func showPanel() {
        let wasHidden = !panel.isVisible
        if wasHidden {
            syncWebViews()
            if !config.rememberLastPage { currentID = config.pages.first?.id }
            positionPanel()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        select(currentIndex, showHUD: false)
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if config.pauseOnClose {
            webViews.values.forEach { $0.pauseAllMediaPlayback(completionHandler: nil) }
        }
        let settingsOpen = settingsWindow?.isVisible ?? false
        if NSApp.isActive && !settingsOpen { NSApp.hide(nil) } // 이전 앱으로 포커스 반환
    }

    @objc func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func positionPanel() {
        let size = panel.frame.size
        switch config.position {
        case .remembered:
            if let o = config.savedOrigin, o.count == 2 {
                let p = NSPoint(x: o[0], y: o[1])
                let r = NSRect(origin: p, size: size)
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) {
                    panel.setFrameOrigin(p)
                    return
                }
            }
            positionBelowStatusItem(size)
        case .center:
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let vf = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
            }
        case .statusItem:
            positionBelowStatusItem(size)
        }
    }

    func positionBelowStatusItem(_ size: NSSize) {
        if let btn = statusItem.button, let win = btn.window {
            let r = win.convertToScreen(btn.convert(btn.bounds, to: nil))
            let vf = (win.screen ?? NSScreen.main)?.visibleFrame ?? r
            var x = r.midX - size.width / 2
            var y = r.minY - size.height - 4
            x = max(vf.minX + 8, min(x, vf.maxX - size.width - 8))
            y = max(vf.minY + 8, y)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 8))
        }
    }

    // MARK: NSWindowDelegate

    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, !isApplying else { return }
        model.config.width = Double(panel.frame.width.rounded())
        model.config.height = Double(panel.frame.height.rounded())
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, !isApplying,
              config.position == .remembered, panel.isVisible else { return }
        model.config.savedOrigin = [Double(panel.frame.origin.x), Double(panel.frame.origin.y)]
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        syncWebViews()
        if panel.isVisible { select(currentIndex, showHUD: false) }
    }

    // MARK: 페이지 전환

    var currentIndex: Int {
        config.pages.firstIndex { $0.id == currentID } ?? 0
    }

    var currentWebView: WKWebView? {
        guard let id = currentID else { return nil }
        return webViews[id]
    }

    func select(_ index: Int, showHUD: Bool) {
        let pages = config.pages
        emptyLabel.isHidden = !pages.isEmpty
        guard !pages.isEmpty else {
            webViews.values.forEach { $0.isHidden = true }
            urlField.stringValue = ""
            return
        }
        let n = pages.count
        let i = ((index % n) + n) % n
        let page = pages[i]
        currentID = page.id
        UserDefaults.standard.set(page.id.uuidString, forKey: "lastPageID")

        let wv = webView(for: page)
        for (id, v) in webViews { v.isHidden = (id != page.id) }
        lastViewed[page.id] = Date()
        if wv.frame != container.bounds { wv.frame = container.bounds }
        if needsNudge.remove(page.id) != nil { nudgeLayout(wv) }
        if findBar.isHidden == false { hideFind() }
        updateTabs()
        updateAddressBar(force: true)
        if panel.isVisible && urlField.currentEditor() == nil { panel.makeFirstResponder(wv) }
        _ = showHUD // 탭 전환 시 이름 표시는 하지 않음
    }

    func normalizedURL(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if !t.contains("://") { t = "https://" + t }
        return URL(string: t)
    }

    func webView(for page: PageConfig) -> WKWebView {
        if let wv = webViews[page.id] { return wv }
        return createWebView(for: page)
    }

    /// popupConfig: 사이트가 새 창을 열 때 WebKit이 넘겨준 설정. 이걸로 만들어야
    /// 로그인 팝업처럼 원래 페이지와 주고받는(window.opener) 동작이 유지됨. 이때 주소는 WebKit이 직접 불러옴
    func createWebView(for page: PageConfig, popupConfig: WKWebViewConfiguration? = nil) -> WKWebView {
        let cfg: WKWebViewConfiguration
        if let popupConfig {
            cfg = popupConfig
        } else {
            cfg = WKWebViewConfiguration()
            // 일반 탭은 로그인 유지, 시크릿 탭은 메모리에만 (탭을 닫거나 앱을 끄면 사라짐)
            cfg.websiteDataStore = page.incognito ? .nonPersistent() : .default()
            cfg.userContentController.addUserScript(muteScript(page.muted))
        }
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.preferences.isElementFullscreenEnabled = true // 영상 전체화면 버튼
        if popupConfig == nil {
            // 우클릭한 링크 주소를 받는 통로 (팝업은 원래 탭과 같은 통로를 공유하므로 한 번만 등록)
            cfg.userContentController.add(contextLinkHandler, name: "mcContextLink")
            cfg.setURLSchemeHandler(startPageHandler, forURLScheme: "menucycle")
            cfg.userContentController.addUserScript(contextLinkScript)
        }
        let wv = MCWebView(frame: container.bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        let ua = page.device.userAgent(custom: config.customUserAgent)
        wv.customUserAgent = ua
        wv.pageZoom = CGFloat(page.zoom)
        wv.uiDelegate = self
        wv.navigationDelegate = self
        if #available(macOS 13.3, *) { wv.isInspectable = true }
        if popupConfig == nil, let u = resumeURL.removeValue(forKey: page.id) ?? normalizedURL(page.url) {
            wv.load(URLRequest(url: u))
        }
        container.addSubview(wv, positioned: .below, relativeTo: nil)
        lastRefresh[page.id] = Date()
        lastViewed[page.id] = Date()

        let id = page.id
        observers[id] = [
            wv.observe(\.url, options: [.new]) { [weak self] _, _ in self?.webStateChanged(id) },
            wv.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.webStateChanged(id) },
            wv.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.webStateChanged(id) },
            wv.observe(\.title, options: [.new]) { [weak self] _, _ in self?.titleChanged(id) },
        ]
        webViews[id] = wv
        webMeta[id] = WebMeta(url: page.url, ua: ua)
        return wv
    }

    func dropWebView(_ id: UUID) {
        observers[id] = nil
        webViews[id]?.removeFromSuperview()
        webViews[id] = nil
        webMeta[id] = nil
        needsNudge.remove(id)
    }

    /// 메모리에서 내리기 (다시 볼 때 마지막 주소로 새로 불러옴)
    func unload(_ id: UUID) {
        if let u = webViews[id]?.url { resumeURL[id] = u }
        dropWebView(id)
    }

    /// 설정에서 주소/모바일 여부가 바뀐 페이지는 새로 만듦
    func syncWebViews() {
        let byID = Dictionary(uniqueKeysWithValues: config.pages.map { ($0.id, $0) })
        for id in Array(webViews.keys) {
            guard let p = byID[id], let m = webMeta[id] else { dropWebView(id); continue }
            if p.url != m.url || p.device.userAgent(custom: config.customUserAgent) != m.ua { dropWebView(id) }
        }
    }

    func webStateChanged(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.followSite(id)
            self.recordVisit(id)
            guard id == self.currentID else { return }
            self.updateAddressBar(force: false)
        }
    }

    /// + 로 만든 탭은 이름·주소가 보고 있는 사이트를 따라감 (다음 실행 때도 그 사이트로 열림)
    func followSite(_ id: UUID) {
        guard let i = config.pages.firstIndex(where: { $0.id == id }), config.pages[i].autoName,
              let u = webViews[id]?.url, let host = u.host, !host.isEmpty else { return }
        let name: String
        if u.scheme == "menucycle" {
            name = config.pages[i].incognito ? "시크릿 탭" : "새 탭"
        } else {
            name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let s = u.absoluteString
        var p = config.pages[i]
        guard p.url != s || p.name != name else { return }
        webMeta[id]?.url = s // 다시 불러오지 않도록 먼저 갱신
        p.url = s
        p.name = name
        model.config.pages[i] = p
    }

    // MARK: 방문 기록 · 시크릿 탭

    func recordVisit(_ id: UUID) {
        guard config.recordHistory, let wv = webViews[id], let u = wv.url,
              lastRecorded[id] != u.absoluteString,
              let p = config.pages.first(where: { $0.id == id }), !p.incognito else { return }
        lastRecorded[id] = u.absoluteString
        history.record(url: u, title: wv.title)
    }

    func titleChanged(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.config.recordHistory, let wv = self.webViews[id],
                  let u = wv.url?.absoluteString, let t = wv.title,
                  let p = self.config.pages.first(where: { $0.id == id }), !p.incognito else { return }
            self.history.updateTitle(url: u, title: t)
        }
    }

    @objc func newIncognitoTab() {
        let page = PageConfig(name: "시크릿 탭", url: startPageURL, autoName: true, incognito: true)
        model.config.pages.append(page)
        currentID = page.id
        if panel.isVisible { select(currentIndex, showHUD: false) } else { showPanel() }
        focusAddressBar()
    }

    @objc func openHistoryWindow() {
        if historyWindow == nil {
            let view = HistoryView(store: history) { [weak self] url, newTab in
                self?.openFromHistory(url, newTab: newTab)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "방문 기록"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 560, height: 520))
            w.center()
            historyWindow = w
        }
        historyWindow?.level = panel.level
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    func openFromHistory(_ s: String, newTab: Bool) {
        guard let u = URL(string: s) else { return }
        if newTab || config.pages.isEmpty {
            let page = PageConfig(name: "새 탭", url: s, autoName: true)
            model.config.pages.append(page)
            currentID = page.id
            showPanel()
        } else {
            showPanel()
            currentWebView?.load(URLRequest(url: u))
        }
    }

    // MARK: 주소창 자동완성 (방문 기록에서, Safari처럼 입력 중인 글자 뒤에 회색으로 채움)

    func controlTextDidBeginEditing(_ obj: Notification) {
        lastTypedLength = 0
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        lastTypedLength = 0
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === urlField,
              let editor = field.currentEditor() as? NSTextView else { return }
        let typed = editor.string
        let len = (typed as NSString).length
        defer { lastTypedLength = len }
        // 지우는 중이거나 공백(검색어)이 있으면 자동완성하지 않음
        guard len > lastTypedLength, !typed.contains(" "),
              let i = currentPageIndex, !config.pages[i].incognito,
              let full = history.complete(typed) else { return }
        let rest = String(full.dropFirst(typed.count))
        guard !rest.isEmpty else { return }
        editor.string = typed + rest
        editor.setSelectedRange(NSRange(location: len, length: (rest as NSString).length))
    }

    @objc func newTab() {
        let page = PageConfig(name: "새 탭", url: startPageURL, autoName: true)
        model.config.pages.append(page)
        currentID = page.id
        if panel.isVisible { select(currentIndex, showHUD: false) } else { showPanel() }
        focusAddressBar()
    }

    var currentPageIndex: Int? {
        guard let id = currentID else { return nil }
        return config.pages.firstIndex { $0.id == id }
    }

    func flash(_ text: String) {
        if config.showHUD { hud.flash(text, in: container) }
    }

    // MARK: 화면 종류 (PC / iPhone / iPad / Android / 직접 입력)

    func popUp(_ menu: NSMenu, under sender: NSView) {
        // 메뉴의 왼쪽 위 모서리를 p에 맞춤. 주소창이 아래에 있으면 버튼 위로 펼침
        let h = menu.size.height
        let p: NSPoint
        if config.addressBarAtBottom {
            p = NSPoint(x: 0, y: sender.isFlipped ? -2 - h : sender.bounds.height + 2 + h)
        } else {
            p = NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.height + 2 : -2)
        }
        menu.popUp(positioning: nil, at: p, in: sender)
    }

    @objc func showDeviceMenu(_ sender: NSButton) {
        guard let i = currentPageIndex else { return }
        let cur = config.pages[i].device
        let m = NSMenu()
        m.autoenablesItems = false
        for d in DeviceMode.allCases {
            let it = NSMenuItem(title: d.title, action: #selector(pickDevice(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = d.rawValue
            it.state = (d == cur) ? .on : .off
            if d == .custom && config.customUserAgent.trimmingCharacters(in: .whitespaces).isEmpty {
                it.title = "직접 입력 (설정 → 일반에서 먼저 입력)"
                it.isEnabled = false
            }
            m.addItem(it)
        }
        popUp(m, under: sender)
    }

    @objc func pickDevice(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let d = DeviceMode(rawValue: raw),
              let id = currentID, let i = currentPageIndex else { return }
        let ua = d.userAgent(custom: config.customUserAgent)
        webMeta[id]?.ua = ua // 탭을 새로 만들지 않고 그 자리에서 바꿈
        if let wv = webViews[id] {
            wv.customUserAgent = ua
            wv.reload()
        }
        model.config.pages[i].device = d
        updateAddressBar(force: false)
        flash(d.short + " 화면")
    }

    // MARK: 음소거

    @objc func toggleMute() {
        guard let id = currentID, let i = currentPageIndex else { return }
        let on = !config.pages[i].muted
        model.config.pages[i].muted = on
        if let wv = webViews[id] {
            let ucc = wv.configuration.userContentController
            ucc.removeAllUserScripts()
            ucc.addUserScript(muteScript(on)) // 다음에 불러오는 페이지에도 적용
            ucc.addUserScript(contextLinkScript)
            wv.evaluateJavaScript("window.__mcSetMuted && window.__mcSetMuted(\(on ? "true" : "false"))",
                                  completionHandler: nil)
        }
        updateAddressBar(force: false)
        rebuildTabs()
        flash(on ? "🔇 음소거" : "🔊 소리 켬")
    }

    // MARK: 확대 / 축소

    func setZoom(_ z: Double) {
        guard let i = currentPageIndex, let wv = currentWebView else { return }
        let v = min(3.0, max(0.5, (z * 10).rounded() / 10))
        wv.pageZoom = CGFloat(v)
        model.config.pages[i].zoom = v
        flash("\(Int((v * 100).rounded()))%")
    }

    @objc func zoomIn() { setZoom(Double(currentWebView?.pageZoom ?? 1) + 0.1) }
    @objc func zoomOut() { setZoom(Double(currentWebView?.pageZoom ?? 1) - 0.1) }
    @objc func zoomReset() { setZoom(1.0) }

    // MARK: 페이지에서 찾기

    func setupFindBar() {
        findBar.material = .menu
        findBar.blendingMode = .withinWindow
        findBar.state = .active
        findBar.wantsLayer = true
        findBar.layer?.cornerRadius = 8
        findBar.frame = NSRect(x: 0, y: 0, width: 300, height: 34)
        findBar.autoresizingMask = [.minXMargin, .minYMargin]
        findBar.isHidden = true

        findField.frame = NSRect(x: 6, y: 6, width: 200, height: 22)
        findField.placeholderString = "페이지에서 찾기"
        findField.sendsSearchStringImmediately = false
        findField.target = self
        findField.action = #selector(findFieldChanged(_:))

        let prev = iconButton("chevron.up", "이전 (⌘⇧G)", #selector(findPrev))
        let next = iconButton("chevron.down", "다음 (⌘G / Enter)", #selector(findNextAction))
        let close = iconButton("xmark", "닫기 (Esc)", #selector(hideFindAction))
        prev.frame = NSRect(x: 212, y: 5, width: 24, height: 24)
        next.frame = NSRect(x: 238, y: 5, width: 24, height: 24)
        close.frame = NSRect(x: 268, y: 5, width: 24, height: 24)
        [findField, prev, next, close].forEach { findBar.addSubview($0) }
        container.addSubview(findBar) // 웹뷰는 항상 맨 아래에 추가되므로 찾기 막대가 위에 보임
    }

    func showFind() {
        guard currentWebView != nil else { return }
        let b = container.bounds
        findBar.setFrameOrigin(NSPoint(x: b.width - findBar.frame.width - 10, y: b.height - findBar.frame.height - 8))
        findBar.removeFromSuperview()
        container.addSubview(findBar)
        findBar.isHidden = false
        panel.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    func hideFind() {
        findBar.isHidden = true
        currentWebView?.evaluateJavaScript("window.getSelection && window.getSelection().removeAllRanges()",
                                           completionHandler: nil)
        if let wv = currentWebView { panel.makeFirstResponder(wv) }
    }

    func find(backwards: Bool) {
        guard let wv = currentWebView else { return }
        if findBar.isHidden { showFind(); return }
        let q = findField.stringValue
        guard !q.isEmpty else { return }
        let c = WKFindConfiguration()
        c.backwards = backwards
        c.caseSensitive = false
        c.wraps = true
        wv.find(q, configuration: c) { [weak self] r in
            self?.findField.textColor = r.matchFound ? .labelColor : .systemRed
        }
    }

    @objc func findFieldChanged(_ sender: NSSearchField) { find(backwards: false) }
    @objc func findNextAction() { find(backwards: false) }
    @objc func findPrev() { find(backwards: true) }
    @objc func hideFindAction() { hideFind() }

    // MARK: PIP (화면 속 화면)

    @objc func togglePiP() {
        guard let wv = currentWebView else { return }
        let js = """
        const vs = Array.from(document.querySelectorAll('video'))
          .filter(v => v.readyState > 0)
          .sort((a, b) => (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight));
        const v = vs[0];
        if (!v) return 'novideo';
        if (v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')) {
          v.webkitSetPresentationMode(v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
          return 'ok';
        }
        if (document.pictureInPictureElement) { await document.exitPictureInPicture(); return 'ok'; }
        if (v.requestPictureInPicture) { await v.requestPictureInPicture(); return 'ok'; }
        return 'unsupported';
        """
        wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let v):
                let s = v as? String
                if s == "novideo" { self?.flash("재생 중인 영상이 없어요") }
                if s == "unsupported" { self?.flash("이 페이지에서는 PIP를 쓸 수 없어요") }
            case .failure:
                self?.flash("PIP를 시작하지 못했어요")
            }
        }
    }

    // MARK: 더 보기 메뉴

    @objc func showMoreMenu(_ sender: NSButton) {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, _ menu: NSMenu) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        }
        add("영상 PIP (화면 속 화면)   ⌘⇧P", #selector(togglePiP), m)
        add("페이지에서 찾기   ⌘F", #selector(findMenuAction), m)
        add("방문 기록   ⌘Y", #selector(openHistoryWindow), m)
        add("새 시크릿 탭   ⌘⇧N", #selector(newIncognitoTab), m)
        m.addItem(.separator())
        let zoomPct = Int(((currentWebView?.pageZoom ?? 1) * 100).rounded())
        let zoomHeader = NSMenuItem(title: "확대 \(zoomPct)%", action: nil, keyEquivalent: "")
        zoomHeader.isEnabled = false
        m.addItem(zoomHeader)
        add("   확대   ⌘+", #selector(zoomIn), m)
        add("   축소   ⌘-", #selector(zoomOut), m)
        add("   원래 크기   ⌘0", #selector(zoomReset), m)
        m.addItem(.separator())

        let refresh = NSMenuItem(title: "자동 새로고침", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let cur = currentPageIndex.map { config.pages[$0].refreshMinutes } ?? 0
        for mins in refreshChoices {
            let it = NSMenuItem(title: mins == 0 ? "끔" : "\(mins)분마다", action: #selector(pickRefresh(_:)), keyEquivalent: "")
            it.target = self
            it.tag = mins
            it.state = (mins == cur) ? .on : .off
            sub.addItem(it)
        }
        refresh.submenu = sub
        m.addItem(refresh)
        m.addItem(.separator())
        let pause = NSMenuItem(title: "창을 닫으면 영상·음악 일시정지", action: #selector(togglePauseOnClose), keyEquivalent: "")
        pause.target = self
        pause.state = config.pauseOnClose ? .on : .off
        m.addItem(pause)
        m.addItem(.separator())
        add("다운로드 폴더 열기", #selector(openDownloads), m)
        popUp(m, under: sender)
    }

    @objc func findMenuAction() { showFind() }

    // MARK: 투명도 (주소창 버튼 → 세로 슬라이더)

    func setupOpacityPopover() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 56, height: 176))
        opacityLabel.frame = NSRect(x: 0, y: 150, width: 56, height: 16)
        opacityLabel.alignment = .center
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        opacitySlider.isVertical = true
        opacitySlider.minValue = 0.3
        opacitySlider.maxValue = 1.0
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.frame = NSRect(x: 18, y: 10, width: 20, height: 134)
        v.addSubview(opacityLabel)
        v.addSubview(opacitySlider)
        let vc = NSViewController()
        vc.view = v
        opacityPopover.contentViewController = vc
        opacityPopover.contentSize = v.frame.size
        opacityPopover.behavior = .transient
    }

    @objc func showOpacity(_ sender: NSButton) {
        if opacityPopover.isShown { opacityPopover.performClose(nil); return }
        opacitySlider.doubleValue = config.opacity
        opacityLabel.stringValue = "\(Int((config.opacity * 100).rounded()))%"
        // 주소창이 아래에 있으면 버튼 위쪽으로, 위에 있으면 아래쪽으로 띄움
        let below: NSRectEdge = sender.isFlipped ? .maxY : .minY
        let above: NSRectEdge = sender.isFlipped ? .minY : .maxY
        opacityPopover.show(relativeTo: sender.bounds, of: sender,
                            preferredEdge: config.addressBarAtBottom ? above : below)
    }

    @objc func opacityChanged(_ sender: NSSlider) {
        let v = (sender.doubleValue * 100).rounded() / 100
        opacityLabel.stringValue = "\(Int((v * 100).rounded()))%"
        if v != config.opacity { model.config.opacity = v }
    }

    @objc func togglePauseOnClose() {
        model.config.pauseOnClose.toggle()
        flash(config.pauseOnClose ? "창 닫으면 일시정지: 켬" : "창 닫으면 일시정지: 끔")
    }

    @objc func pickRefresh(_ sender: NSMenuItem) {
        guard let id = currentID, let i = currentPageIndex else { return }
        model.config.pages[i].refreshMinutes = sender.tag
        lastRefresh[id] = Date()
        flash(sender.tag == 0 ? "자동 새로고침 끔" : "\(sender.tag)분마다 새로고침")
    }

    @objc func openDownloads() {
        NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    // MARK: 자동 새로고침 · 메모리에서 내리기 (30초마다 확인)

    func maintenance() {
        let now = Date()
        for p in config.pages {
            guard let wv = webViews[p.id] else { continue }
            if p.refreshMinutes > 0 {
                let last = lastRefresh[p.id] ?? now
                if now.timeIntervalSince(last) >= Double(p.refreshMinutes) * 60 {
                    lastRefresh[p.id] = now
                    wv.reload()
                }
                continue // 자동 새로고침 탭은 내리지 않음
            }
            guard config.unloadMinutes > 0, p.id != currentID else { continue }
            let seen = lastViewed[p.id] ?? now
            guard now.timeIntervalSince(seen) >= Double(config.unloadMinutes) * 60 else { continue }
            let id = p.id
            wv.requestMediaPlaybackState { [weak self] state in
                guard let self, state != .playing, id != self.currentID else { return }
                self.unload(id)
            }
        }
    }

    // MARK: 사이트 아이콘 (파비콘)

    func iconFileURL(_ id: UUID) -> URL {
        let dir = ConfigStore.url.deletingLastPathComponent().appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(id.uuidString)
    }

    func favicon(for id: UUID) -> NSImage? {
        if let img = favicons[id] { return img }
        guard let img = NSImage(contentsOf: iconFileURL(id)), img.isValid else { return nil }
        img.size = NSSize(width: 14, height: 14)
        favicons[id] = img
        return img
    }

    func fetchFavicon(_ id: UUID, _ wv: WKWebView) {
        guard let host = wv.url?.host, faviconHost[id] != host else { return }
        faviconHost[id] = host
        let js = """
        (function(){
          var sel = ['link[rel~="icon"][sizes="32x32"]','link[rel~="icon"]','link[rel="shortcut icon"]','link[rel="apple-touch-icon"]'];
          for (var i=0;i<sel.length;i++){ var l=document.querySelector(sel[i]); if(l&&l.href) return l.href; }
          return location.origin + '/favicon.ico';
        })()
        """
        wv.evaluateJavaScript(js) { [weak self] r, _ in
            guard let s = r as? String, let u = URL(string: s) else { return }
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let data, let img = NSImage(data: data), img.isValid else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    img.size = NSSize(width: 14, height: 14)
                    self.favicons[id] = img
                    try? data.write(to: self.iconFileURL(id), options: .atomic)
                    self.rebuildTabs()
                }
            }.resume()
        }
    }

    // MARK: 레이아웃 바로잡기
    // 숨겨진 상태나 로딩 중 크기가 바뀌면 일부 사이트(YouTube 등)가 좁은 폭으로 그려진 채 남음.
    // 사용자가 창 크기를 바꾸면 고쳐지는 것과 같은 효과를 내기 위해 폭을 1pt 바꿨다 되돌림.
    func nudgeLayout(_ wv: WKWebView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak wv] in
            guard let self, let wv, !wv.isHidden else { return }
            let s = self.container.bounds.size
            wv.setFrameSize(NSSize(width: s.width - 1, height: s.height))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                wv.setFrameSize(s)
                wv.evaluateJavaScript("window.dispatchEvent(new Event('resize'))", completionHandler: nil)
            }
        }
    }

    // MARK: WKNavigationDelegate · 다운로드

    func pageID(of wv: WKWebView) -> UUID? {
        webViews.first { $0.value === wv }?.key
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let id = pageID(of: webView) else { return }
        if webView.isHidden || !panel.isVisible { needsNudge.insert(id) } else { nudgeLayout(webView) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // ⌥(Option)+클릭한 링크는 시스템 기본 브라우저로
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.option),
           let u = navigationAction.request.url, u.scheme == "http" || u.scheme == "https" {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        // ⌘+클릭한 링크는 브라우저처럼 뒤쪽 새 탭으로 (현재 탭은 그대로)
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command),
           let u = navigationAction.request.url, u.scheme == "http" || u.scheme == "https" {
            openInNewTab(u, from: webView, activate: false)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        // 그냥 .allow 를 주면 WebKit이 링크를 클릭할 때 '이 주소를 맡은 앱'(유튜브 웹 앱 등)이 있는지 확인해서
        // 그 앱으로 넘겨버림. 앱으로 넘기지 말고 이 창 안에서 열도록 하는 값 (allow + 2 = AllowWithoutTryingAppLink)
        let allowInPlace = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
        decisionHandler(allowInPlace)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let h = navigationResponse.response as? HTTPURLResponse,
           let cd = h.value(forHTTPHeaderField: "Content-Disposition"),
           cd.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var dest = dir.appendingPathComponent(suggestedFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        downloadDest[ObjectIdentifier(download)] = dest
        flash("⬇︎ 다운로드 중: \(dest.lastPathComponent)")
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let dest = downloadDest.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Dock의 다운로드 스택이 통통 튀도록 알림
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.DownloadFileFinished"),
                                                     object: dest.path)
        flash("✓ 다운로드 완료: \(dest.lastPathComponent)")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDest.removeValue(forKey: ObjectIdentifier(download))
        flash("다운로드 실패")
    }

    @objc func closeTab(_ sender: NSMenuItem) {
        closeTab(at: sender.tag)
    }

    /// ⌘W: 현재 탭 닫기. 마지막 남은 탭이면 탭은 두고 창만 닫음
    @objc func closeCurrentTab() {
        guard let i = currentPageIndex, config.pages.count > 1 else { hidePanel(); return }
        closeTab(at: i)
    }

    func closeTab(at i: Int) {
        guard config.pages.indices.contains(i) else { return }
        var p = config.pages[i]
        if let u = webViews[p.id]?.url?.absoluteString { p.url = u } // 다시 열 때 보던 주소로
        closedTabs.append((p, i))
        if closedTabs.count > 20 { closedTabs.removeFirst() }

        if p.id == currentID && config.pages.count > 1 {
            // 브라우저처럼 오른쪽 탭으로, 없으면 왼쪽 탭으로
            currentID = i + 1 < config.pages.count ? config.pages[i + 1].id : config.pages[i - 1].id
        }
        model.config.pages.remove(at: i)
        if panel.isVisible { select(currentIndex, showHUD: false) }
    }

    /// ⌘⇧T: 마지막으로 닫은 탭 다시 열기
    @objc func reopenClosedTab() {
        guard let last = closedTabs.popLast() else { flash("다시 열 탭이 없어요"); return }
        var p = last.page
        if config.pages.contains(where: { $0.id == p.id }) { p.id = UUID() }
        model.config.pages.insert(p, at: min(last.index, config.pages.count))
        currentID = p.id
        if panel.isVisible { select(currentIndex, showHUD: false) } else { showPanel() }
    }

    func rebuildTabs() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, p) in config.pages.enumerated() {
            // 기본은 번호만 (보고 있는 사이트가 옆사람에게 보이지 않게). 설정에서 이름 표시 가능
            let label = config.showTabNames ? "\(i + 1) \(p.name)" : "\(i + 1)"
            let b = TabButton(title: "\(p.incognito ? "🕶 " : "")\(label)\(p.muted ? " 🔇" : "")",
                              target: nil, action: nil)
            b.owner = self
            b.toolTip = "클릭: 열기 · 좌우로 끌기: 순서 변경 · 우클릭: 닫기"
            let menu = NSMenu()
            let close = NSMenuItem(title: "탭 닫기", action: #selector(closeTab(_:)), keyEquivalent: "")
            close.target = self
            close.tag = i
            menu.addItem(close)
            b.menu = menu
            b.bezelStyle = .recessed
            b.setButtonType(.pushOnPushOff)
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.lineBreakMode = .byTruncatingTail
            b.tag = i
            b.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            tabStack.addArrangedSubview(b)
        }
        updateTabs()
    }

    func updateTabs() {
        let cur = currentIndex
        for case let b as NSButton in tabStack.arrangedSubviews {
            b.state = (b.tag == cur) ? .on : .off
        }
    }

    @objc func tabClicked(_ sender: NSButton) { select(sender.tag, showHUD: false) }

    // MARK: 탭 드래그로 순서 변경

    func tabDragBegan(_ b: TabButton) {
        b.alphaValue = 0.55
    }

    func tabDragMoved(_ b: TabButton, windowPoint: NSPoint) {
        let n = tabStack.arrangedSubviews.count
        guard n > 1, let from = tabStack.arrangedSubviews.firstIndex(of: b) else { return }
        let p = tabStack.convert(windowPoint, from: nil)
        let slot = tabStack.bounds.width / CGFloat(n)
        let to = max(0, min(n - 1, Int(p.x / slot)))
        guard to != from else { return }
        tabStack.removeArrangedSubview(b)
        tabStack.insertArrangedSubview(b, at: to)
        tabStack.layoutSubtreeIfNeeded()
    }

    func tabDragEnded(_ b: TabButton) {
        b.alphaValue = 1
        // 버튼의 tag = 원래 순서. 화면에 놓인 순서대로 페이지 목록 재배열
        let order = tabStack.arrangedSubviews.compactMap { ($0 as? NSButton)?.tag }
        let pages = config.pages
        guard order.count == pages.count, order != Array(pages.indices) else { return }
        let reordered = order.map { pages[$0] }
        DispatchQueue.main.async { [weak self] in
            self?.model.config.pages = reordered // apply()가 탭을 다시 그림
        }
    }

    // MARK: 주소창

    func updateAddressBar(force: Bool) {
        let wv = currentWebView
        backButton.isEnabled = wv?.canGoBack ?? false
        forwardButton.isEnabled = wv?.canGoForward ?? false
        if let i = currentPageIndex {
            let p = config.pages[i]
            deviceButton.image = NSImage(systemSymbolName: p.device.symbol, accessibilityDescription: p.device.title)
            deviceButton.contentTintColor = p.device == .desktop ? nil : .controlAccentColor
            deviceButton.toolTip = "화면 종류: \(p.device.title) (클릭해서 변경)"
            muteButton.image = NSImage(systemSymbolName: p.muted ? "speaker.slash.fill" : "speaker.wave.2",
                                       accessibilityDescription: "음소거")
            muteButton.contentTintColor = p.muted ? .systemRed : nil
            muteButton.toolTip = p.muted ? "음소거 해제 (⌘⇧M)" : "음소거 (⌘⇧M)"
            // 시크릿 탭은 주소창 막대를 보라색으로
            addressBar.wantsLayer = true
            addressBar.layer?.backgroundColor = p.incognito
                ? NSColor.systemPurple.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
            urlField.placeholderString = p.incognito
                ? "시크릿 탭 · 기록과 쿠키가 남지 않아요" : "주소 또는 검색어 입력 (⌘L)"
        }
        if force || urlField.currentEditor() == nil {
            if let u = wv?.url, u.scheme == "menucycle" {
                urlField.stringValue = "" // 시작 페이지: 바로 입력할 수 있게 비워 둠
            } else if let u = wv?.url?.absoluteString {
                urlField.stringValue = u
            } else if config.pages.indices.contains(currentIndex) {
                urlField.stringValue = config.pages[currentIndex].url
            }
        }
    }

    func focusAddressBar() {
        guard config.showAddressBar else { return }
        panel.makeFirstResponder(urlField)
        urlField.selectText(nil)
    }

    func resolveInput(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.contains("://"), let u = URL(string: t) { return u }
        let looksLikeHost = !t.contains(" ") && (t.contains(".") || t.hasPrefix("localhost"))
        if looksLikeHost, let u = URL(string: "https://" + t) { return u }
        return config.searchEngine.searchURL(t)
    }

    @objc func urlEntered(_ sender: NSTextField) {
        guard let u = resolveInput(sender.stringValue), let wv = currentWebView else { return }
        wv.load(URLRequest(url: u))
        panel.makeFirstResponder(wv)
    }

    @objc func goBack() { currentWebView?.goBack() }
    @objc func goForward() { currentWebView?.goForward() }
    @objc func reloadCurrent() { currentWebView?.reload() }

    /// 홈: 설정에서 등록한 탭은 등록한 주소로,
    /// +로 만든 탭(주소가 보는 사이트를 따라가는 탭)은 검색 엔진 첫 화면으로
    @objc func goHome() {
        guard let i = currentPageIndex else { return }
        let p = config.pages[i]
        let home = p.autoName ? startPageURL : p.url
        guard let u = normalizedURL(home) else { return }
        currentWebView?.load(URLRequest(url: u))
    }

    // MARK: 메뉴바 아이콘

    @objc func statusClicked(_ sender: Any?) {
        guard let e = NSApp.currentEvent else { return }
        if e.type == .rightMouseUp || e.modifierFlags.contains(.control) {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        let cur = currentIndex
        for (i, p) in config.pages.enumerated() {
            let item = NSMenuItem(title: "\(i + 1). \(p.name)", action: #selector(menuJump(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == cur) ? .on : .off
            m.addItem(item)
        }
        if !config.pages.isEmpty { m.addItem(.separator()) }

        func add(_ title: String, _ sel: Selector) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            m.addItem(it)
        }
        add("페이지 추가…", #selector(addPageDialog))
        if !config.pages.isEmpty { add("현재 페이지 새로고침", #selector(reloadCurrent)) }
        m.addItem(.separator())
        let top = NSMenuItem(title: "항상 위에 표시", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        top.target = self
        top.state = config.alwaysOnTop ? .on : .off
        m.addItem(top)
        let blur = NSMenuItem(title: "다른 곳 클릭 시 닫기", action: #selector(toggleCloseOnBlur), keyEquivalent: "")
        blur.target = self
        blur.state = config.closeOnBlur ? .on : .off
        m.addItem(blur)
        m.addItem(.separator())
        if model.updateAvailable {
            add("⬆︎ 새 버전 설치하고 다시 시작", #selector(installUpdateFromMenu))
            m.addItem(.separator())
        }
        add("새 시크릿 탭", #selector(newIncognitoTab))
        add("방문 기록", #selector(openHistoryWindow))
        add("다운로드 폴더 열기", #selector(openDownloads))
        add("설정…", #selector(openSettings))
        m.addItem(.separator())
        add("종료", #selector(quit))
        return m
    }

    @objc func menuJump(_ sender: NSMenuItem) {
        guard config.pages.indices.contains(sender.tag) else { return }
        currentID = config.pages[sender.tag].id
        let keep = config.rememberLastPage
        if !panel.isVisible && !keep {
            // 선택한 페이지로 열기 위해 이번만 기억 사용
            syncWebViews()
            positionPanel()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            select(sender.tag, showHUD: false)
        } else {
            showPanel()
        }
    }

    @objc func addPageDialog() {
        let alert = NSAlert()
        alert.messageText = "페이지 추가"
        alert.addButton(withTitle: "추가")
        alert.addButton(withTitle: "취소")

        let v = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 84))
        let name = NSTextField(frame: NSRect(x: 0, y: 58, width: 300, height: 24))
        name.placeholderString = "이름 (예: ChatGPT)"
        let url = NSTextField(frame: NSRect(x: 0, y: 28, width: 300, height: 24))
        url.placeholderString = "https://chatgpt.com"
        if panel.isVisible, let cur = currentWebView?.url?.absoluteString { url.stringValue = cur }
        let mobile = NSButton(checkboxWithTitle: "모바일 화면으로 열기", target: nil, action: nil)
        mobile.frame = NSRect(x: 0, y: 0, width: 300, height: 20)
        [name, url, mobile].forEach { v.addSubview($0) }
        alert.accessoryView = v
        alert.window.initialFirstResponder = name

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let u = url.stringValue.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return }
        var n = name.stringValue.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { n = normalizedURL(u)?.host ?? u }

        let page = PageConfig(name: n, url: u, device: mobile.state == .on ? .iphone : .desktop)
        model.config.pages.append(page)
        currentID = page.id
        showPanel()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "MenuCycle 설정"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        settingsWindow?.level = panel.level // 패널은 그대로 두고 설정 창을 그 위에
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func installUpdateFromMenu() { updater.install() }

    @objc func toggleAlwaysOnTop() { model.config.alwaysOnTop.toggle() }
    @objc func toggleCloseOnBlur() { model.config.closeOnBlur.toggle() }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // 새 창으로 열리는 링크(구글 검색 결과, 우클릭 → 새 창, 로그인 팝업 등)는 경로와 관계없이 항상 앱 안 새 탭.
        // WebKit이 준 설정으로 웹뷰를 만들어 돌려줘야 원래 페이지(window.opener)와 연결이 유지되어 로그인 콜백이 동작함.
        // 시스템 브라우저는 ⌥+클릭 / 우클릭 메뉴로 사용자가 직접 고를 때만 사용
        let page = newTabPage(url: navigationAction.request.url, from: webView)
        let wv = createWebView(for: page, popupConfig: configuration)
        popupOpener[page.id] = pageID(of: webView)
        insertTab(page, after: webView, activate: true)
        return wv
    }

    /// 로그인 화면으로 보이는 주소 (Google, Apple, Microsoft, GitHub, 카카오, 네이버 등)
    func isAuthURL(_ u: URL?) -> Bool {
        guard let u, let h = u.host?.lowercased() else { return false }
        let hosts = ["accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com",
                     "github.com", "facebook.com", "kauth.kakao.com", "accounts.kakao.com", "nid.naver.com",
                     "twitter.com", "x.com", "discord.com", "id.atlassian.com", "slack.com", "auth0.com", "okta.com"]
        if hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return true }
        let path = u.path.lowercased()
        return ["oauth", "authorize", "/sso", "signin", "/login"].contains { path.contains($0) }
    }

    /// 링크에서 열리는 새 탭: 원래 탭의 화면 종류를 이어받고, 이름·주소는 사이트를 따라감
    func newTabPage(url: URL?, from source: WKWebView) -> PageConfig {
        let s = url?.absoluteString ?? ""
        var page = PageConfig(name: "새 탭", url: s.isEmpty ? "about:blank" : s, autoName: true)
        if let sid = pageID(of: source), let src = config.pages.first(where: { $0.id == sid }) {
            page.device = src.device
            page.incognito = src.incognito // 시크릿 탭에서 연 링크는 시크릿 탭으로
        }
        return page
    }

    /// 원래 탭 바로 오른쪽에 탭 추가
    func insertTab(_ page: PageConfig, after source: WKWebView, activate: Bool) {
        var at = config.pages.count
        if let sid = pageID(of: source), let i = config.pages.firstIndex(where: { $0.id == sid }) { at = i + 1 }
        model.config.pages.insert(page, at: min(at, config.pages.count))
        if activate {
            currentID = page.id
            select(currentIndex, showHUD: false)
        } else {
            flash("새 탭에서 열림")
        }
    }

    func openInNewTab(_ url: URL, from source: WKWebView, activate: Bool) {
        let page = newTabPage(url: url, from: source)
        insertTab(page, after: source, activate: activate)
        if !activate {
            let wv = webView(for: page) // 뒤에서 미리 불러오기
            wv.isHidden = true
        }
    }

    /// 로그인 팝업처럼 페이지가 스스로 창을 닫으면(window.close) 그 탭도 닫음
    func webViewDidClose(_ webView: WKWebView) {
        guard let id = pageID(of: webView), let i = config.pages.firstIndex(where: { $0.id == id }),
              config.pages.count > 1 else { return }
        let opener = popupOpener.removeValue(forKey: id) ?? nil
        closeTab(at: i)
        // 로그인이 끝나 팝업이 닫히면 로그인을 시작한 원래 탭으로 돌아감
        if let opener, config.pages.contains(where: { $0.id == opener }) {
            currentID = opener
            if panel.isVisible { select(currentIndex, showHUD: false) }
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = parameters.allowsDirectories
        p.begin { r in completionHandler(r == .OK ? p.urls : nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        showAlert(frame.request.url?.host ?? "", message)
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = frame.request.url?.host ?? ""
        a.informativeText = message
        a.addButton(withTitle: "확인")
        a.addButton(withTitle: "취소")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
}

// MARK: - 진입점

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Dock 아이콘 없이 메뉴바에만
app.run()
