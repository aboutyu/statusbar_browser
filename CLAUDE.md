# CLAUDE.md

이 파일은 이 저장소에서 작업할 때 Claude Code(claude.ai/code)에게 제공하는 가이드입니다.

## 프로젝트 개요

바브라우저(Bar Browser)는 SwiftUI + WebKit으로 만든 macOS 메뉴바 미니 웹브라우저입니다. Dock 아이콘 없이
(`LSUIElement = YES`) 메뉴바에만 상주하며, 팝오버 형태의 창에 `WKWebView`를 띄워 마지막으로 방문한 URL을
실행 시 복원합니다. 사용자는 창 크기를 조절하고, 화면 모드(다크/라이트/시스템)를 바꾸고, 전역 단축키를
설정하고, 로그인 시 자동 실행을 켤 수 있습니다 — 그리고 팝오버를 닫아도 재생 중이던 오디오/영상은 계속
재생됩니다.

제품명: MenubarBrowser(타깃), 번들 ID `com.yutaehun.MenubarBrowser`.

## 빌드 / 실행 / 린트

표준 Xcode 프로젝트입니다 — 저장소에 CLI 테스트 스위트, 패키지 매니저, 린트 설정은 없습니다.

- `MenubarBrowser.xcodeproj`를 Xcode로 열고 `MenubarBrowser` 스킴(macOS 앱)을 실행합니다.
- 커맨드라인 빌드: `xcodebuild -project MenubarBrowser.xcodeproj -scheme MenubarBrowser -configuration Debug build`
- 현재 정의된 테스트 타깃은 없습니다.
- 배포 타깃: macOS 14.6(타깃 빌드 설정 기준). 프로젝트 레벨 설정은 15.7로 되어 있지만, 앱에는 타깃 레벨
  값이 우선 적용됩니다.
- 현재 버전: `MARKETING_VERSION = 1.0.2`, `CURRENT_PROJECT_VERSION = 6` (`project.pbxproj`의 타깃 빌드
  설정 참고).

## 아키텍처

Debug/Release 두 개의 Xcode 빌드 구성이 `MenubarBrowser.xcodeproj/project.pbxproj`에 거의 동일한 설정으로
존재합니다. `Info.plist`는 `INFOPLIST_KEY_*` 빌드 설정에서 자동 생성되며(`GENERATE_INFOPLIST_FILE = YES`)
직접 편집하는 파일이 아닙니다 — 저장소에 커밋된 `Info.plist`는 거의 비어 있는 베이스 템플릿일 뿐입니다.
Info.plist 항목을 추가할 때는 `Info.plist`를 직접 수정하지 말고, Debug와 Release **양쪽 구성 모두에**
`INFOPLIST_KEY_*` 빌드 설정으로 추가하세요. `MenubarBrowser.entitlements`는 현재 빈 dict로, 활성화된
샌드박스/권한(capability)이 없습니다.

`MenubarBrowser/`에 있는 핵심 런타임 구성 요소:

- **AppDelegate.swift** — `NSStatusItem`으로 메뉴바 아이콘을 직접 소유하며, 팝오버 자체는 `NSPopover`나
  SwiftUI의 `MenuBarExtra`가 아니라 **커스텀 borderless `NSWindow`**(이 파일 안의 private 클래스
  `PopoverWindow`)로 구현되어 있습니다. 이렇게 만든 이유는 파일 상단 헤더 주석과 코드 내 주석에 모두
  설명되어 있으며 크게 두 가지입니다.
  - `MenuBarExtra`는 드롭다운을 코드로 열고 닫는 공개 API가 없는데, 전역 단축키(⌃⌥⌘B, Carbon
    `RegisterEventHotKey`)로 팝오버를 토글하려면 이 기능이 반드시 필요합니다.
  - `NSPopover`를 `.transient`로 쓰면 닫힐 때 내부 콘텐츠 창을 실제로 없애버려서, 그 순간 `WKWebView`가
    "어떤 창에도 속하지 않은" 상태가 됩니다. WebKit은 이를 페이지가 사라진 것으로 인식해 재생 중이던
    오디오/영상(예: 유튜브)을 스스로 멈춥니다. 커스텀 `PopoverWindow`는 절대 `close()`하지 않고
    `orderOut()` 및 `alphaValue = 0` + `ignoresMouseEvents = true`로만 숨기기 때문에, 창(과 그 안의
    WKWebView)이 계속 살아있어 팝오버를 닫아도(=메뉴바 아이콘 밖 클릭) 미디어 재생이 끊기지 않습니다.
  - `PopoverWindow`는 `.statusBar` 레벨에 `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
    .stationary]` collection behavior로 떠 있습니다(`.popUpMenu`/`.normal` 레벨은 Space 전환 시 재생이
    끊기는 문제가 있었음 — 코드 주석 참고). 닫기 동작은 `NSPopover`의 transient-close 대신 직접 구현되어
    있습니다: 바깥 클릭은 전역 `NSEvent` 모니터, ⌘Tab 등 키보드 전환은 `didResignActiveNotification`,
    Esc는 로컬 모니터(URL 입력창 등) + `PopoverWindow.keyDown`/`cancelOperation`(웹페이지가 처리하지 않은
    Esc만 올라옴)으로 처리합니다.
  - 숨길 때 창은 key 상태로 남지 않아야 합니다: `hidePopoverWindow(restoreFocus: true)`(Esc/단축키/아이콘
    클릭)는 팝오버를 열기 전 활성 앱(`previousActiveApp`)으로 포커스를 돌려줍니다. 그러지 않으면 투명한
    팝오버 창의 WKWebView가 키 입력을 계속 받습니다(예: 유튜브 단축키 오작동). `orderOut()`/`NSApp.hide`는
    미디어를 멈추므로 쓰지 않습니다.
  - 숨김 상태의 창은 `parkHiddenPopoverWindow()`로 화면 밖에 모서리 1pt만 걸쳐 둡니다. Space 전환(세 손가락
    스와이프) 애니메이션이 alphaValue를 무시하고 창을 그려서, 제자리에 두면 전환할 때마다 깜빡이기
    때문입니다. 이때 WebKit은 페이지를 `document.hidden = true`로 만들고, 모바일 UA로 열린 유튜브 등은
    이를 보고 재생을 멈춥니다 — 그래서 `WebView.swift`의 `pageVisibilityScriptSource`가 모든 프레임에서
    `document.hidden`/`visibilityState`를 항상 "보임"으로 덮어쓰고 `visibilitychange`를 차단합니다.
    "닫아도 계속 재생"은 창 위치/occlusion이 아니라 이 스크립트에 의존합니다.
  - `canBecomeKey`를 `true`로 오버라이드했는데(borderless 창은 기본적으로 key window가 될 수 없음),
    URL 입력창이 키보드 포커스를 받으려면 필요합니다.
  - AppDelegate는 **크기 조절 기능**도 담당합니다. `PopoverView`의 `ResizeStrip`이 드래그 중에는
    `.resizePopoverBy`(프레임마다 이동량 델타)를, 드래그가 끝나면 `.resizePopoverDragEnded`(최종 크기
    저장)를 post하고, AppDelegate가 이를 받아 `clampedSize`(화면 크기 기준 — 최소 크기는 화면 세로의
    1/3 정사각형, 최대 크기는 화면 visibleFrame. 시작 크기 `PopoverSizing.initialSize`는 세로 = visibleFrame
    높이 전체, 가로 = 그 3/8)로 clamp한 뒤
    `UserDefaults`(`lastPopoverWidth`/`lastPopoverHeight`)에 저장해 다음 실행 시 복원합니다. 설정의
    "사이즈 초기화" 버튼이 post하는 `.resetPopoverSize`는 기본 크기로 되돌리고 메뉴바 아이콘 기준으로
    다시 중앙 정렬합니다.
  - **화면 모드**(`AppearanceMode` enum: `.dark`/`.light`/`.system`)는 `UserDefaults` 키
    `"appearanceMode"`(`SettingsPopMenu`의 `@AppStorage`와 공유)에 저장되고 `NSApp.appearance`로
    적용됩니다.
  - **About/설정 창**은 SwiftUI `Window` scene이 아니라 AppDelegate가 직접 생성하고 띄우는 순수 AppKit
    `NSWindow`입니다(`handleOpenAbout`/`handleOpenSettings`, `PopoverView`의 톱니바퀴 메뉴에서 post하는
    `.openAboutWindow`/`.openSettingsWindow` 알림으로 트리거됨). 이 창들이 열려 있는 동안 AppDelegate는
    `NSApp.setActivationPolicy`를 `.accessory`와 `.regular` 사이로 전환해(보조 창이 하나라도 열려 있는
    동안 Dock/Cmd-Tab에 앱 아이콘이 보이도록) 관리하며, 두 창의 `NSWindowDelegate`로서 마지막 창이 닫히면
    정책을 다시 `.accessory`로 되돌립니다.
  - 그 외에 `UserDefaults.didChangeNotification`을 관찰해 설정에서 단축키 토글
    (`@AppStorage("shortcutEnabled")`)이나 화면 모드가 바뀔 때마다 이를 다시 동기화합니다.
- **MenubarBrowserApp.swift** — `@main` 진입점. `@NSApplicationDelegateAdaptor`로 `AppDelegate`를
  연결합니다. **빈 `Settings { EmptyView() }` scene** 하나만 선언하는데, 이는 SwiftUI 앱이 최소 하나의
  `Scene`을 가져야 한다는 요구사항을 채우기 위한 것일 뿐 사용자에게 보이는 일은 없습니다. 메뉴바 아이콘/
  팝오버와 About/설정 창은 전부 scene이 아니라 `AppDelegate`가 AppKit으로 직접 만들고 관리합니다 —
  SwiftUI `Window` scene을 의도적으로 쓰지 않는 이유는, macOS 14에서는 이런 scene이 실행 시점에 억제할
  방법 없이 자동으로 열릴 수 있기 때문입니다(`.defaultLaunchBehavior(.suppressed)`는 macOS 15+ 필요,
  이 프로젝트의 배포 타깃 14.6보다 높음). 빈 Settings scene이 기본으로 추가하는 "Settings… ⌘," 메뉴는
  빈 창을 열어버리므로 `.commands { CommandGroup(replacing: .appSettings) }`로 `.openSettingsWindow`를
  post하는 항목으로 교체해 두었습니다.
- **PopoverView.swift** — 팝오버 콘텐츠: 뒤로가기 버튼, URL 입력창, 톱니바퀴 `Menu`(설정 / 바브라우저에
  관하여 / 종료), `WebView`, 그리고 두 개의 `ResizeStrip` 오버레이(오른쪽 가장자리 = 가로 크기 조절,
  아래쪽 가장자리 = 세로 크기 조절 — 드래그하면 위에서 설명한 `.resizePopoverBy`/`.resizePopoverDragEnded`
  를 post하고 AppDelegate가 처리). `NotificationCenter`를 (바인딩/state 대신) 이용해 공유 `WKWebView` 및
  AppDelegate와 통신합니다: `.goBack`/`.loadURL`은 여기서 post되고 `WebView`가 관찰하며,
  `.openSettingsWindow`/`.openAboutWindow`는 톱니바퀴 메뉴에서 post되고 `AppDelegate`가 관찰해 두 창을
  띄우기 전에 팝오버 자체를 먼저 닫습니다.
- **WebView.swift** — `WKWebView`를 감싼 `NSViewRepresentable`. `WebViewHolder.shared`가 살아있는
  `WKWebView` 인스턴스에 대한 싱글턴 참조를 들고 있어서, 다른 뷰(메뉴 액션, 알림 핸들러)가 prop drilling
  없이 이를 제어할 수 있습니다. 좁은 팝오버 안에서도 사이트가 모바일 레이아웃으로 보이도록 커스텀 모바일
  Safari User-Agent를 설정합니다. 주소 변화는 `didFinish`가 아니라 `url`/`canGoBack` KVO로 관찰합니다
  (pushState로 이동하는 SPA는 `didFinish`가 오지 않음) — 이를 `currentURL`/`canGoBack` 바인딩과
  `UserDefaults` 키 `"lastURL"`에 반영합니다. 로드 실패는 `loadError` 바인딩으로 `PopoverView`의 배너에
  표시합니다. `WKUIDelegate`로 JS alert/confirm/prompt와 파일 업로드를 시트로 처리하고(팝오버가
  `.statusBar` 레벨이라 일반 모달은 뒤에 가려짐), 스크립트의 `window.open`(OAuth 로그인 팝업 등)은
  `PopupWebWindowController`로 실제 팝업 창을 만들어 opener 연결을 유지합니다. `target="_blank"` 링크
  클릭은 같은 웹뷰에서 엽니다.
- **SettingsPopMenu.swift** — 설정 창 UI, 총 4개 행으로 구성됩니다: 단축키(`@AppStorage
  ("shortcutEnabled")` 토글), 로그인시 실행(`SMAppService.mainApp.register()/.unregister()`를 호출하고,
  사용자가 시스템 설정 → 로그인 항목에서 직접 껐을 수도 있으므로 `.onAppear`에서 `SMAppService.mainApp
  .status`로 실제 상태를 다시 동기화하며, 등록 실패 시 작은 빨간 오류 텍스트를 표시), 사이즈 초기화
  (`.resetPopoverSize`를 post하는 버튼), 화면모드(`@AppStorage("appearanceMode")`에 바인딩된 세그먼트
  `Picker`, 값은 `"dark"`/`"light"`/`"system"`이며 `AppDelegate.AppearanceMode`가 이를 소비). 알려진
  SwiftUI 레이아웃 함정: 단축키 키캡 `HStack`(Image + Image + Image + Text가 `.cornerRadius`/`.overlay`
  안에 여러 단계로 중첩됨)은 `.overlay` 바로 뒤에 `.fixedSize()`가 없으면 마지막 `Text("B")`가 조용히
  너비 0으로 잘려나갑니다 — 오프스크린 `ImageRenderer` 재현으로 확인된 문제로, 뷰 코드만 읽어서는 바로
  알아채기 어렵습니다. 루트 뷰에는 `.fixedSize(horizontal: false, vertical: true)`도 적용되어 있는데,
  `NSHostingController`가 창 생성 시점에 높이를 잘못 추정해 아래쪽이 잘리는 문제 때문입니다.
- **AboutAppMenu.swift** — About 창. `Bundle.main.infoDictionary`에서
  `CFBundleShortVersionString`/`CFBundleVersion`을 읽어와서 버전 텍스트가 빌드 설정과 자동으로 동기화되게
  합니다.


## App Store 심사 관련 작업 노트

이 브랜치의 최근 히스토리에는 App Store 심사/빌드번호 증가(타깃 빌드 설정의 `MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION` 참고)와 수출 규정 준수(`ITSAppUsesNonExemptEncryption`) 처리가 `Info.plist`를
직접 건드리는 대신 `INFOPLIST_KEY_*` 빌드 설정으로 이루어져 있습니다 — 앞으로 컴플라이언스/메타데이터를
변경할 때도 같은 패턴(Debug/Release 두 구성 모두 `project.pbxproj`에서 수정)을 따르세요.
