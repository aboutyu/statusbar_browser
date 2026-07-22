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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {

            HStack {
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
                
                
                
                Menu {
                    Button("설정") {
                        NotificationCenter.default.post(name: .closePopover, object: nil)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.setActivationPolicy(.regular)
                            openWindow(id: "settings_window")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }

                    Button("바브라우저에 관하여") {
                        NotificationCenter.default.post(name: .closePopover, object: nil)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.setActivationPolicy(.regular)
                            openWindow(id: "about_window")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }

                    Divider()

                    Button("종료") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundColor(.primary)
                        .contentShape(Rectangle()) // 클릭 영역 확보
                }
                .menuStyle(.borderlessButton) // 💡 macOS에서 배경 없이 아이콘만 남기는 스타일
                .menuIndicator(.hidden)
                .fixedSize() // 주변 레이아웃에 영향을 주지 않도록 고정
                
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
        .onReceive(NotificationCenter.default.publisher(for: .goBack)) { _ in
            WebViewHolder.shared.webView?.goBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadURL)) { noti in
            if let url = noti.object as? URL {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        }
    }

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
}

