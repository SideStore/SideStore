//
//  SplashView.swift
//  SideStore
//
//  Created by Magesh K on 14/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

@MainActor
final class SplashViewModel: ObservableObject {
    @Published var isReadyToExit = false
}

struct SplashView: View {
    @ObservedObject var viewModel: SplashViewModel
    var onFinished: () -> Void

    @State private var didBeginExit = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                UltraStoreLaunchLogo(logoSize: min(geometry.size.width * 0.48, 220))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("UltraStore")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: viewModel.isReadyToExit) {
            guard viewModel.isReadyToExit, !didBeginExit else { return }
            didBeginExit = true
            onFinished()
        }
    }
}

struct UltraStoreLaunchLogo: View {
    let logoSize: CGFloat

    var body: some View {
        ZStack {
            UltraStoreLogoBowl()
                .stroke(.white, style: StrokeStyle(lineWidth: logoSize * 0.11, lineCap: .round))
            UltraStoreLaunchArrow()
                .fill(.white)
        }
        .frame(width: logoSize, height: logoSize)
    }
}

private struct UltraStoreLogoBowl: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.29, y: rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.width * 0.29, y: rect.height * 0.63))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.71, y: rect.height * 0.63),
            control1: CGPoint(x: rect.width * 0.29, y: rect.height * 0.94),
            control2: CGPoint(x: rect.width * 0.71, y: rect.height * 0.94)
        )
        return path
    }
}

private struct UltraStoreLaunchArrow: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var shaft = Path()
        shaft.move(to: point(0.71, 0.63))
        shaft.addLine(to: point(0.71, 0.34))
        var arrow = shaft.strokedPath(StrokeStyle(lineWidth: rect.width * 0.11, lineCap: .butt))
        var head = Path()
        head.move(to: point(0.71, 0.20))
        head.addLine(to: point(0.81, 0.34))
        head.addLine(to: point(0.61, 0.34))
        head.closeSubpath()
        arrow.addPath(head)
        return arrow
    }
}
