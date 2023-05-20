//
//  AppIconsShowcase.swift
//  SideStore
//
//  Created by Fabian Thies on 25.02.23.
//  Copyright © 2023 SideStore. All rights reserved.
//

import SwiftUI

struct AppIconsShowcase: View {

    @State var animationProgress = 0.0
    @State var animation2Progress = 0.0

    var body: some View {
        VStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Image(uiImage: UIImage(named: "AppIcon")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 0.2 * proxy.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
                        .offset(x: -0.3*proxy.size.width * self.animationProgress, y: -30)
                        .rotationEffect(.degrees(-20 * self.animationProgress))
                        .shadow(radius: 8 * self.animationProgress)

                    Image(uiImage: UIImage(named: "AppIcon")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 0.25 * proxy.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
                        .offset(x: -0.15*proxy.size.width * self.animationProgress, y: -10)
                        .rotationEffect(.degrees(-10 * self.animationProgress))
                        .shadow(radius: 12 * self.animationProgress)

                    Image(uiImage: UIImage(named: "AppIcon")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 0.2 * proxy.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
                        .offset(x: self.animationProgress*0.3*proxy.size.width, y: -30)
                        .rotationEffect(.degrees(self.animationProgress*20))
                        .shadow(radius: 8 * self.animationProgress)

                    Image(uiImage: UIImage(named: "AppIcon")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 0.25 * proxy.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
                        .offset(x: self.animationProgress * 0.15*proxy.size.width, y: -10)
                        .rotationEffect(.degrees(self.animationProgress * 10))
                        .shadow(radius: 12 * self.animationProgress)

                    Image(uiImage: UIImage(named: "AppIcon")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 0.3 * proxy.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
                        .shadow(radius: 16 * self.animationProgress + 8 * self.animation2Progress)
                        .scaleEffect(1.0 + 0.05 * self.animation2Progress)
                }
                .frame(maxWidth: proxy.size.width)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring()) {
                    self.animationProgress = 1.0
                    self.animation2Progress = 1.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring()) {
                        self.animation2Progress = 0.0
                    }
                }
            }
        }
    }
}

struct AppIconsShowcase_Previews: PreviewProvider {
    static var previews: some View {
        AppIconsShowcase()
            .frame(height: 150)
    }
}
