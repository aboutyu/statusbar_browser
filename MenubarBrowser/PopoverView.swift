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

    private var minSize: NSSize {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return PopoverSizing.minSize(forScreen: screenFrame)
    }

    var body: some View {
        content
            .overlay(alignment: .trailing) {
                ResizeStrip(axis: .horizontal)
            }
            .overlay(alignment: .bottom) {
                ResizeStrip(axis: .vertical)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

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
        .frame(minWidth: minSize.width, minHeight: minSize.height)
        .onReceive(NotificationCenter.default.publisher(for: .goBack)) { _ in
            WebViewHolder.shared.webView?.goBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadURL)) { noti in
            if let url = noti.object as? URL {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                NotificationCenter.default.post(name: .goBack, object: nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.06))
            .clipShape(Circle())
            .foregroundStyle(canGoBack ? Color.primary : Color.primary.opacity(0.3))
            .disabled(!canGoBack)

            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("URL 입력", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        loadURL()
                        removeFocus()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Menu {
                Button("설정") {
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                }

                Button("바브라우저에 관하여") {
                    NotificationCenter.default.post(name: .openAboutWindow, object: nil)
                }

                Divider()

                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton) // 💡 macOS에서 배경 없이 아이콘만 남기는 스타일
            .menuIndicator(.hidden)
            .fixedSize() // 주변 레이아웃에 영향을 주지 않도록 고정
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial) // 라이트/다크 모드 모두 자동으로 대응되는 네이티브 툴바 느낌
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

// 📐 오른쪽 가장자리(가로)/아래쪽 가장자리(세로)를 드래그해 한 축만 조절하는 핸들.
// 모서리 대각선 드래그는 지원하지 않음 (min/max는 AppDelegate가 clamp)
private struct ResizeStrip: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    @State private var lastTranslation: CGSize = .zero

    private var cursor: NSCursor {
        axis == .horizontal ? .resizeLeftRight : .resizeUpDown
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: axis == .horizontal ? 6 : nil,
                   height: axis == .vertical ? 6 : nil)
            .frame(maxWidth: axis == .vertical ? .infinity : nil,
                   maxHeight: axis == .horizontal ? .infinity : nil)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        cursor.set() // 빠르게 드래그하면 hover 영역을 벗어나는 순간이 있어 매 프레임 다시 세팅
                        let step: CGSize
                        switch axis {
                        case .horizontal:
                            step = CGSize(width: value.translation.width - lastTranslation.width, height: 0)
                        case .vertical:
                            step = CGSize(width: 0, height: value.translation.height - lastTranslation.height)
                        }
                        lastTranslation = value.translation
                        NotificationCenter.default.post(name: .resizePopoverBy, object: step)
                    }
                    .onEnded { _ in
                        lastTranslation = .zero
                        NotificationCenter.default.post(name: .resizePopoverDragEnded, object: nil)
                    }
            )
            .onHover { hovering in
                (hovering ? cursor : NSCursor.arrow).set()
            }
    }
}

