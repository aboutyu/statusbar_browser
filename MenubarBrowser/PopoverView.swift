//
//  PopoverView.swift
//  MenubarBrowser
//
//  Created by yutaehun on 1/21/26.
//

import SwiftUI
internal import WebKit

struct PopoverView: View {
    @State private var urlText = ""
    @State private var canGoBack = false

    var body: some View {
        VStack(spacing: 8) {

            HStack {
                // ◀️ 뒤로가기
                Button {
                    NotificationCenter.default.post(name: .goBack, object: nil)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

                // 🔗 URL 입력창
                TextField("URL 입력", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        loadURL()
                        removeFocus()
                    }
                
                Button {
                    loadURL()
                    removeFocus()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .disabled(!canGoBack)
            }
            .padding(.horizontal)

            WebView(urlText: $urlText, canGoBack: $canGoBack)
                .background(
                    // 🖱️ 텍스트박스 외 클릭 시 포커스 제거
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            removeFocus()
                        }
                )
        }
        .padding(.top, 10)
        .frame(minWidth: 450, minHeight: 600)
        .onAppear {
            setupBackNavigation()
        }
    }

    // MARK: - Helpers

    private func loadURL() {
        var text = urlText.trimmingCharacters(in: .whitespaces)
        if !text.hasPrefix("http") {
            text = "https://" + text
        }

        if let url = URL(string: text) {
            NotificationCenter.default.post(name: .loadURL, object: url)
        }
    }

    private func removeFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func setupBackNavigation() {
        NotificationCenter.default.addObserver(
            forName: .goBack,
            object: nil,
            queue: .main
        ) { _ in
            WebViewHolder.shared.webView?.goBack()
        }

        NotificationCenter.default.addObserver(
            forName: .loadURL,
            object: nil,
            queue: .main
        ) { noti in
            if let url = noti.object as? URL {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        }
    }
}

