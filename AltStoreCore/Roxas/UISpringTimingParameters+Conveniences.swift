//
//  UISpringTimingParameters+Conveniences.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

public extension UISpringTimingParameters {
    struct SpringStiffness: RawRepresentable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
        public typealias RawValue = CGFloat
        public typealias FloatLiteralType = Double
        public typealias IntegerLiteralType = Int
        
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
    
    @objc(initWithMass:stiffness:dampingRatio:)
    convenience init(mass: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat) {
        self.init(mass: mass, stiffness: stiffness, dampingRatio: dampingRatio, initialVelocity: .zero)
    }
    
    @objc(initWithMass:stiffness:dampingRatio:initialVelocity:)
    convenience init(mass: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat, initialVelocity: CGVector) {
        let criticalDamping = 2.0 * sqrt(mass * stiffness)
        let damping = dampingRatio * criticalDamping
        self.init(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
    }
    
    @objc(initWithStiffness:dampingRatio:)
    convenience init(stiffness: CGFloat, dampingRatio: CGFloat) {
        self.init(stiffness: stiffness, dampingRatio: dampingRatio, initialVelocity: .zero)
    }
    
    @objc(initWithStiffness:dampingRatio:initialVelocity:)
    convenience init(stiffness: CGFloat, dampingRatio: CGFloat, initialVelocity: CGVector) {
        let mass: CGFloat = 3.0
        self.init(mass: mass, stiffness: stiffness, dampingRatio: dampingRatio, initialVelocity: initialVelocity)
    }
}

public extension UIViewPropertyAnimator {
    @objc(initWithSpringTimingParameters:animations:)
    convenience init(springTimingParameters timingParameters: UISpringTimingParameters, animations: (() -> Void)?) {
        self.init(duration: 0, timingParameters: timingParameters)
        if let animations = animations {
            self.addAnimations(animations)
        }
    }
}
