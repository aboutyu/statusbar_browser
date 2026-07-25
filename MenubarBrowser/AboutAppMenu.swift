//
//  AboutAppMenu.swift
//  MenubarBrowser
//
//  Created by yutaehun on 3/12/26.
//

import SwiftUI

struct AboutAppMenu: View {
    // 📌 앱 프로젝트 설정(Info)에서 버전과 빌드 번호를 자동으로 가져오는 변수
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 0) {
            Image("BarAppIcon")
                .resizable()
                .antialiased(true)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80) // 크기를 조금 더 키웠습니다.
                .padding(.top, 40)
            
            Text("바브라우저")
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 10)
            
            Spacer().frame(height: 25)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("개발자")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Text("유태훈")
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Text("버   전")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Text("\(appVersion)")
                }
                
                Text("Copyright 2026 유태훈 all right reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
            .font(.system(size: 13))
            
            Spacer().frame(height: 15)
        }
        .frame(width: 300, height: 280) // 창 크기 고정
        .background(Color(NSColor.windowBackgroundColor))
    }
}
