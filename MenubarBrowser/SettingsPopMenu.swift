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
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
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

                Divider()
                    .padding(.horizontal, 20)

                // 2. 로그인시 자동 실행 영역
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
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // 시스템 설정(로그인 항목)에서 직접 끈 경우도 반영되도록 실제 상태를 다시 읽어옴
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
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
