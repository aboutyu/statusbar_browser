//
//  WebView.swift
//  MenubarBrowser
//
//  Created by yutaehun on 1/21/26.
//

import SwiftUI
@preconcurrency internal import WebKit

final class WebViewHolder {
    static let shared = WebViewHolder()
    var webView: WKWebView?
}

extension Notification.Name {
    static let goBack = Notification.Name("goBack")
    static let loadURL = Notification.Name("loadURL")
    // AppDelegate가 팝오버 창의 occlusionState 변화를 관찰하다가, Space 스와이프 등으로
    // 잠깐 가려졌던 창이 다시 보이게 되면 post한다. WebView는 이를 받아 재생 중이었던
    // <video>/<audio>가 그 사이 WebKit에 의해 일시정지됐다면 다시 재생시킨다.
    static let resumeMediaIfNeeded = Notification.Name("resumeMediaIfNeeded")
}

private let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
                              "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
                              "Version/17.0 Mobile/15E148 Safari/604.1"

// 🙈 팝오버를 닫거나(창을 화면 밖으로 치워둠) Space를 전환하면 WebKit이 페이지를
// document.hidden = true로 바꾸는데, 모바일 유튜브 등은 이를 보고 스스로 재생을 멈춘다(모바일
// User-Agent라 iOS처럼 백그라운드 재생을 막는 동작을 함). 메뉴바 브라우저는 "닫아도 계속 재생"이
// 핵심 기능이라, 페이지에는 항상 보이는 상태로 보고하고 visibilitychange 이벤트도 전달하지 않는다.
// 진짜 가시성은 아래 미디어 재개 스크립트가 쓸 수 있도록 window.__barBrowserReallyHidden으로 남긴다.
// window 캡처 단계 리스너를 문서 시작 시점에 가장 먼저 등록하므로 페이지의 어떤 리스너보다 먼저 실행된다.
private let pageVisibilityScriptSource = """
(function() {
    if (window.__barBrowserVisibilityInstalled) { return; }
    window.__barBrowserVisibilityInstalled = true;

    var hiddenDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'hidden');
    window.__barBrowserReallyHidden = function() {
        return hiddenDescriptor && hiddenDescriptor.get ? hiddenDescriptor.get.call(document) : false;
    };

    function define(name, value) {
        try {
            Object.defineProperty(Document.prototype, name, { get: function() { return value; }, configurable: true });
        } catch (e) {}
    }
    define('hidden', false);
    define('webkitHidden', false);
    define('visibilityState', 'visible');
    define('webkitVisibilityState', 'visible');

    ['visibilitychange', 'webkitvisibilitychange'].forEach(function(type) {
        window.addEventListener(type, function(e) { e.stopImmediatePropagation(); }, true);
    });
})();
"""

// 🔊 Space 전환(트랙패드 스와이프)처럼 창이 잠깐 occluded 상태가 되는 동안 WebKit이 재생 중이던
// 미디어를 스스로 멈추는 경우가 있어서, 페이지에 재생 의도(사용자가 최근에 play를 눌렀는지)를
// 기록해두고 .resumeMediaIfNeeded 알림을 받으면 그 의도에 맞춰 다시 play()를 호출한다.
//
// - play/pause는 버블링되지 않지만 캡처 단계로는 document에서 모두 받을 수 있어서, DOM 변경마다
//   문서 전체를 다시 훑는 MutationObserver 없이 재생 의도를 기록한다.
// - evaluateJavaScript는 메인 프레임에서만 실행되므로, 재개 요청을 postMessage로 하위 iframe
//   (임베드된 유튜브 플레이어 등)에 차례로 전달한다. 스크립트 자체는 모든 프레임에 주입된다.
private let mediaResumeScriptSource = """
(function() {
    if (window.__barBrowserMediaResumeInstalled) { return; }
    window.__barBrowserMediaResumeInstalled = true;

    document.addEventListener('play', function(e) {
        if (e.target instanceof HTMLMediaElement) { e.target.dataset.barBrowserWantsPlaying = '1'; }
    }, true);
    document.addEventListener('pause', function(e) {
        var el = e.target;
        if (!(el instanceof HTMLMediaElement)) { return; }
        // 끝까지 재생됐거나, 페이지가 화면에 보이는 상태에서 멈췄다면 사용자가 직접 멈춘 것으로 간주한다.
        // (document.hidden은 위 스크립트가 항상 false로 덮어쓰므로 진짜 가시성을 따로 확인한다)
        var reallyHidden = window.__barBrowserReallyHidden ? window.__barBrowserReallyHidden() : document.hidden;
        if (el.ended || !reallyHidden) { el.dataset.barBrowserWantsPlaying = '0'; }
    }, true);

    function resumeHere() {
        document.querySelectorAll('video, audio').forEach(function(el) {
            if (el.dataset.barBrowserWantsPlaying === '1' && el.paused && !el.ended) {
                el.play().catch(function() {});
            }
        });
    }

    function forwardToFrames() {
        for (var i = 0; i < window.frames.length; i++) {
            try { window.frames[i].postMessage({ __barBrowserResumeMedia: true }, '*'); } catch (e) {}
        }
    }

    window.addEventListener('message', function(e) {
        if (e.source === window.parent && e.data && e.data.__barBrowserResumeMedia === true) {
            resumeHere();
            forwardToFrames();
        }
    });

    window.__barBrowserResumeMedia = function() {
        resumeHere();
        forwardToFrames();
    };
})();
"""

struct WebView: NSViewRepresentable {
    @Binding var currentURL: URL?
    @Binding var canGoBack: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: pageVisibilityScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let resumeScript = WKUserScript(
            source: mediaResumeScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(resumeScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // 📱 모바일 User-Agent
        webView.customUserAgent = mobileUserAgent

        // 🧭 Safari와 유사한 동작
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // 🔁 마지막 URL 복원
        let savedURL = UserDefaults.standard.string(forKey: "lastURL")

        WebViewHolder.shared.webView = webView
        context.coordinator.observe(webView)

        if let startURL = savedURL, let url = URL(string: startURL) {
            webView.load(URLRequest(url: url))
        }

        // WKWebView는 프로세스 전체에서 한 번만 만들어지는 싱글턴이라 별도 해제 없이 유지한다.
        NotificationCenter.default.addObserver(forName: .resumeMediaIfNeeded, object: nil, queue: .main) { [weak webView] _ in
            webView?.evaluateJavaScript("window.__barBrowserResumeMedia && window.__barBrowserResumeMedia();")
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        private var observations: [NSKeyValueObservation] = []
        private var popupControllers: [PopupWebWindowController] = []

        init(_ parent: WebView) {
            self.parent = parent
        }

        // didFinish만으로는 pushState로 이동하는 SPA(유튜브 등)의 주소 변화를 놓치므로,
        // url/canGoBack을 KVO로 직접 관찰해 URL창·뒤로가기 버튼·마지막 URL을 갱신한다.
        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                    DispatchQueue.main.async { self?.urlDidChange(webView.url) }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                    DispatchQueue.main.async { self?.parent.canGoBack = webView.canGoBack }
                }
            ]
        }

        private func urlDidChange(_ url: URL?) {
            guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
            parent.currentURL = url
            // 💾 마지막 URL 저장
            UserDefaults.standard.set(url.absoluteString, forKey: "lastURL")
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportLoadError(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportLoadError(error)
        }

        private func reportLoadError(_ error: Error) {
            let nsError = error as NSError
            // 사용자가 다른 곳으로 이동해서 취소된 로드, 다운로드 등으로 정책상 중단된 로드는 오류가 아니다.
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 204) { return }
            parent.loadError = "페이지를 열 수 없습니다: \(nsError.localizedDescription)"
        }

        // 장시간 백그라운드 재생 등으로 WebContent 프로세스가 죽으면 빈 화면으로 남으므로 다시 불러온다.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // MARK: New windows

        // 🔗 target="_blank" 링크 클릭은 Safari처럼 같은 웹뷰에서 엽니다.
        // 스크립트의 window.open(로그인 팝업 등)은 opener 연결(postMessage, window.opener)이 있어야
        // 동작하므로 실제 팝업 창을 만들어 그 웹뷰를 돌려준다.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }

            if navigationAction.navigationType == .linkActivated {
                webView.load(navigationAction.request)
                return nil
            }

            let controller = PopupWebWindowController(configuration: configuration, windowFeatures: windowFeatures)
            controller.onClose = { [weak self, weak controller] in
                self?.popupControllers.removeAll { $0 === controller }
            }
            popupControllers.append(controller)
            controller.show()
            return controller.webView
        }

        // MARK: JavaScript panels / file upload

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            WebPanels.alert(message: message, in: webView.window, completionHandler: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            WebPanels.confirm(message: message, in: webView.window, completionHandler: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            WebPanels.prompt(prompt, defaultText: defaultText, in: webView.window, completionHandler: completionHandler)
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            WebPanels.openFiles(parameters, in: webView.window, completionHandler: completionHandler)
        }
    }
}

// MARK: - JavaScript 패널

// 팝오버 창은 .statusBar 레벨이라 일반 모달(runModal) 패널은 그 뒤에 가려진다.
// 그래서 웹뷰가 속한 창에 시트로 붙여서 띄운다.
private enum WebPanels {
    static func alert(message: String, in window: NSWindow?, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "확인")
        present(alert, in: window) { _ in completionHandler() }
    }

    static func confirm(message: String, in window: NSWindow?, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        present(alert, in: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    static func prompt(_ prompt: String, defaultText: String?, in window: NSWindow?,
                       completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        present(alert, in: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    static func openFiles(_ parameters: WKOpenPanelParameters, in window: NSWindow?,
                          completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window, window.isVisible, window.alphaValue > 0 {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?,
                                completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible, window.alphaValue > 0 {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            completionHandler(alert.runModal())
        }
    }
}

// MARK: - window.open 팝업 창

// 로그인(OAuth) 팝업처럼 opener와 연결된 새 창이 필요한 경우를 위한 단순한 브라우저 창.
// 팝오버(.statusBar 레벨) 위에 보이도록 같은 레벨로 띄우고, 앱이 비활성화되면 함께 숨긴다.
final class PopupWebWindowController: NSObject, NSWindowDelegate, WKUIDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private var titleObservation: NSKeyValueObservation?
    var onClose: (() -> Void)?

    init(configuration: WKWebViewConfiguration, windowFeatures: WKWindowFeatures) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = mobileUserAgent

        let width = windowFeatures.width.map { CGFloat($0.doubleValue) } ?? 480
        let height = windowFeatures.height.map { CGFloat($0.doubleValue) } ?? 640
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(width, 320), height: max(height, 320)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        webView.uiDelegate = self
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.hidesOnDeactivate = true
        window.delegate = self
        window.title = "바브라우저"
        window.center()

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            if let title = webView.title, !title.isEmpty {
                self?.window.title = title
            }
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 페이지가 window.close()를 호출(로그인 완료 등)하면 창을 닫는다.
    func webViewDidClose(_ webView: WKWebView) {
        window.close()
    }

    // 팝업 안에서 또 열리는 창은 같은 팝업 웹뷰에서 연다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        WebPanels.alert(message: message, in: window, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        WebPanels.confirm(message: message, in: window, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        WebPanels.prompt(prompt, defaultText: defaultText, in: window, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        WebPanels.openFiles(parameters, in: window, completionHandler: completionHandler)
    }

    func windowWillClose(_ notification: Notification) {
        titleObservation = nil
        webView.stopLoading()
        onClose?()
    }
}
