//
//  WebView.swift
//  MenubarBrowser
//
//  Created by yutaehun on 1/21/26.
//

import SwiftUI
internal import WebKit

final class WebViewHolder {
    static let shared = WebViewHolder()
    var webView: WKWebView?
}

extension Notification.Name {
    static let goBack = Notification.Name("goBack")
    static let loadURL = Notification.Name("loadURL")
}


struct WebView: NSViewRepresentable {
    @Binding var urlText: String
    @Binding var canGoBack: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // 📱 모바일 User-Agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
                                  "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
                                  "Version/17.0 Mobile/15E148 Safari/604.1"

        // 🧭 Safari와 유사한 동작
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // 🔁 마지막 URL 복원
        let savedURL = UserDefaults.standard.string(forKey: "lastURL")

        WebViewHolder.shared.webView = webView

        if let startURL = savedURL, let url = URL(string: startURL) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }

            DispatchQueue.main.async {
                self.parent.urlText = url.absoluteString
                self.parent.canGoBack = webView.canGoBack

                // 💾 마지막 URL 저장
                UserDefaults.standard.set(url.absoluteString, forKey: "lastURL")
            }
        }

        // 🔗 target="_blank" 등 새 창 요청을 Safari처럼 같은 웹뷰에서 엽니다.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
