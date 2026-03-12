//
//  SettingsPopMenu.swift
//  MenubarBrowser
//
//  Created by yutaehun on 3/11/26.
//

import SwiftUI

struct SettingsPopMenu: View {
    @State private var shortcutAction = true
    @State private var launchAtLogin = true
    
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
                    
                    Spacer().frame(width: 20)
                }
                .padding(.vertical, 15)
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
    }
}
