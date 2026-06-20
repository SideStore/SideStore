//
//  RSTHelperFile.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
public func RSTDegreesFromRadians(_ radians: CGFloat) -> CGFloat {
    return radians * (180.0 / .pi)
}

public func RSTRadiansFromDegrees(_ degrees: CGFloat) -> CGFloat {
    return (degrees * .pi) / 180.0
}

public func CGFloatEqualToFloat(_ float1: CGFloat, _ float2: CGFloat) -> Bool {
    if float1 == float2 {
        return true
    }
    if abs(float1 - float2) < .ulpOfOne {
        return true
    }
    return false
}

public func rst_dispatch_sync_on_main_thread(_ block: () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.sync(execute: block)
    }
}

private var sharedApplication: UIApplication? {
    let sharedSelector = NSSelectorFromString("sharedApplication")
    guard UIApplication.responds(to: sharedSelector) else { return nil }
    let shared = UIApplication.perform(sharedSelector)
    return shared?.takeUnretainedValue() as? UIApplication
}

public func RSTBeginBackgroundTask(name: String) -> UIBackgroundTaskIdentifier {
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    guard let app = sharedApplication else { return backgroundTask }
    backgroundTask = app.beginBackgroundTask(withName: name) {
        RSTEndBackgroundTask(&backgroundTask)
    }
    return backgroundTask
}

public func RSTEndBackgroundTask(_ backgroundTask: inout UIBackgroundTaskIdentifier) {
    guard let app = sharedApplication else { return }
    app.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
}
