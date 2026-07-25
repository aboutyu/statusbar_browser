//
//  SettingsPopMenu.swift
//  MenubarBrowser
//
//  Created by yutaehun on 3/11/26.
//

import SwiftUI
import ServiceManagement

struct SettingsPopMenu: View {
    @AppStorage("shortcutEnabled") private var shortcutAction = true
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                shortcutRow
                Divider().padding(.horizontal, 20)
                launchAtLoginRow
                resetSizeRow
                Divider().padding(.horizontal, 20)
                appearanceRow
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .frame(width: 300) // 스크린샷에 맞춰 너비 고정
        .padding(.vertical, 10)
        // NSHostingController가 창 생성 시점에 높이를 잘못 추정해 아래가 잘리는 문제가 있어서,
        // 콘텐츠의 실제 높이에 맞춰 세로 크기를 강제로 계산하게 한다.
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // 시스템 설정(로그인 항목)에서 직접 끈 경우도 반영되도록 실제 상태를 다시 읽어옴
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // 1. 단축키 영역
    private var shortcutRow: some View {
        HStack {
            Spacer().frame(width: 20)

            Text("단축키")
                .frame(alignment: .trailing)

            Spacer().frame(width: 10)

            HStack(spacing: 4) {
                Image(systemName: "control")
                Image(systemName: "option")
                Image(systemName: "command")
                Text("B")
            }
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor)) // 시스템 컨트롤 배경색
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .fixedSize()

            Spacer()

            Toggle("", isOn: $shortcutAction)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()

            Spacer().frame(width: 20)
        }
        .padding(.vertical, 15)
    }

    // 2. 로그인시 자동 실행 영역
    private var launchAtLoginRow: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer().frame(width: 20)

                Text("로그인시 실행")
                    .frame(alignment: .trailing)

                Spacer()

                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .labelsHidden() // 라벨 숨김
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Spacer().frame(width: 20)
            }
            .padding(.vertical, 15)

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider().padding(.horizontal, 20)
        }
    }

    // 3. 브라우저 창 사이즈 초기화
    private var resetSizeRow: some View {
        HStack {
            Spacer().frame(width: 20)

            Text("사이즈 초기화")
                .frame(alignment: .trailing)

            Spacer()

            Button("확인") {
                NotificationCenter.default.post(name: .resetPopoverSize, object: nil)
            }
            .buttonStyle(.bordered)

            Spacer().frame(width: 20)
        }
        .padding(.vertical, 15)
    }

    // 4. 화면 모드 (다크/라이트/시스템 설정)
    private var appearanceRow: some View {
        HStack {
            Spacer().frame(width: 20)

            Text("화면모드")
                .frame(alignment: .trailing)

            Spacer()

            Picker("", selection: $appearanceMode) {
                Text("다크").tag("dark")
                Text("라이트").tag("light")
                Text("시스템 설정").tag("system")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer().frame(width: 20)
        }
        .padding(.vertical, 15)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "설정 실패: \(error.localizedDescription)"
            // 실패 시 실제 시스템 상태로 토글을 되돌림
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
