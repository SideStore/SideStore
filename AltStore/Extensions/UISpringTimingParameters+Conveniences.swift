//
//  UISpringTimingParameters+Conveniences.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit

public extension UISpringTimingParameters {
    struct SpringStiffness: RawRepresentable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
        public let rawValue: CGFloat
        
        public init(rawValue: CGFloat) {
            self.rawValue = rawValue
        }
        
        public init(floatLiteral value: Double) {
            self.rawValue = CGFloat(value)
        }
        
        public init(integerLiteral value: Int) {
            self.rawValue = CGFloat(value)
        }
        
        public static let `default`: SpringStiffness = 750.0
        public static let system: SpringStiffness = 1000.0
    }
    
    convenience init(mass: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat) {
        self.init(mass: mass, stiffness: stiffness, dampingRatio: dampingRatio, initialVelocity: .zero)
    }
    
    convenience init(mass: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat, initialVelocity: CGVector) {
        let criticalDamping = 2.0 * sqrt(mass * stiffness)
        let damping = dampingRatio * criticalDamping
        self.init(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
    }
    
    convenience init(stiffness: CGFloat, dampingRatio: CGFloat) {
        self.init(stiffness: stiffness, dampingRatio: dampingRatio, initialVelocity: .zero)
    }
    
    convenience init(stiffness: CGFloat, dampingRatio: CGFloat, initialVelocity: CGVector) {
        let mass: CGFloat = 3.0
        self.init(mass: mass, stiffness: stiffness, dampingRatio: dampingRatio, initialVelocity: initialVelocity)
    }
}

public extension UIViewPropertyAnimator {
    convenience init(springTimingParameters timingParameters: UISpringTimingParameters, animations: (() -> Void)?) {
        self.init(duration: 0, timingParameters: timingParameters)
        if let animations = animations {
            self.addAnimations(animations)
        }
    }
}
