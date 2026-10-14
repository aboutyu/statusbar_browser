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
    @State private var currentURL: URL?
    @State private var canGoBack = false
    @State private var loadError: String?
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        content
            .overlay(alignment: .trailing) {
                ResizeStrip(axis: .horizontal)
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                ResizeStrip(axis: .vertical)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let loadError {
                errorBanner(loadError)
            }

            WebView(currentURL: $currentURL, canGoBack: $canGoBack, loadError: $loadError)
                .background(
                    // 🖱️ 텍스트박스 외 클릭 시 포커스 제거
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            removeFocus()
                        }
                )
        }
        // 입력 중에는 페이지 이동으로 URL창 내용을 덮어쓰지 않고, 포커스를 잃으면(제출 없이
        // 빠져나가면) 현재 페이지 주소로 되돌린다.
        .onChange(of: currentURL) { _, newURL in
            if !isURLFieldFocused, let newURL {
                urlText = newURL.absoluteString
            }
        }
        .onChange(of: isURLFieldFocused) { _, focused in
            if !focused, let currentURL {
                urlText = currentURL.absoluteString
            }
        }
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

                TextField("URL 또는 검색어 입력", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isURLFieldFocused)
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

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                loadError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    private func loadURL() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let url = Self.resolveInput(text) {
            NotificationCenter.default.post(name: .loadURL, object: url)
        }
    }

    // 주소창 입력을 URL로 해석한다.
    // - http/https 스킴이 명시된 주소는 그대로
    // - 공백 없이 도메인/localhost/IP처럼 보이면 https:// 를 붙여서
    // - 그 외(띄어쓰기가 있거나 점이 없는 단어 등)는 검색어로 취급
    // "httpbin.org"처럼 http로 시작하는 도메인이나 "localhost:3000"("localhost"가 스킴으로
    // 파싱됨)을 잘못 처리하지 않도록 접두어 문자열 비교가 아니라 실제 스킴을 확인한다.
    private static func resolveInput(_ text: String) -> URL? {
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host != nil {
            return url
        }

        let looksLikeHost = !text.contains(where: \.isWhitespace)
            && (text.contains(".") || text.lowercased().hasPrefix("localhost"))
        if looksLikeHost, let url = URL(string: "https://" + text), url.host != nil {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        return components?.url
    }

    private func removeFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

private enum ResizeAxis {
    case horizontal, vertical
}

// 📐 오른쪽 가장자리(가로)/아래쪽 가장자리(세로)를 드래그해 한 축만 조절하는 핸들.
// 모서리 대각선 드래그는 지원하지 않음 (min/max는 AppDelegate가 clamp)
//
// SwiftUI onHover + NSCursor.set() 조합으로 구현했을 때는 커서 갱신이 AppKit의
// cursor-rect 무효화 루틴을 타지 않아, 빠르게 드래그하거나 다른 뷰의 hover와 겹치는
// 타이밍에 리사이즈 커서가 안 뜨거나 원래 화살표로 안 돌아오는 경우가 있었다.
// resetCursorRects()로 커서 영역을 등록하는 표준 AppKit 방식이 훨씬 안정적이라
// 이 핸들 전체(커서 + 드래그)를 NSView로 직접 구현한다.
private final class ResizeHandleView: NSView {
    let axis: ResizeAxis
    // 창 좌표(locationInWindow)가 아니라 화면 좌표를 쓴다. 세로 리사이즈는 위쪽 가장자리를
    // 고정하느라 창의 origin.y가 매 프레임 바뀌는데, 창 좌표로 계산하면 이전 점이 그만큼
    // 어긋나 이동량이 m, 0, m, 0…으로 번갈아 나와 창이 커서의 절반 속도로만 따라온다.
    private var lastPoint: NSPoint = .zero

    init(axis: ResizeAxis) {
        self.axis = axis
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let delta: CGSize
        switch axis {
        case .horizontal:
            delta = CGSize(width: point.x - lastPoint.x, height: 0)
        case .vertical:
            // AppKit 좌표계는 y가 위로 증가하므로, 아래로 드래그할 때 높이가 커지도록 부호를 뒤집는다.
            delta = CGSize(width: 0, height: lastPoint.y - point.y)
        }
        lastPoint = point
        NotificationCenter.default.post(name: .resizePopoverBy, object: delta)
    }

    override func mouseUp(with event: NSEvent) {
        NotificationCenter.default.post(name: .resizePopoverDragEnded, object: nil)
    }
}

private struct ResizeStrip: NSViewRepresentable {
    let axis: ResizeAxis

    func makeNSView(context: Context) -> ResizeHandleView {
        ResizeHandleView(axis: axis)
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {}
}

