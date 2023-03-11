//
//  SideStoreAppDelegate.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import AVFoundation
import Intents
import UIKit
import UserNotifications

import AltSign
import SideStoreCore
import EmotionalDamage
import RoxasUIKit

open class SideStoreAppDelegate: UIResponder, UIApplicationDelegate {

}

public extension SideStoreAppDelegate {
    static let openPatreonSettingsDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".OpenPatreonSettingsDeepLinkNotification")
    static let importAppDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".ImportAppDeepLinkNotification")
    static let addSourceDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".AddSourceDeepLinkNotification")

    static let appBackupDidFinish = Notification.Name(Bundle.Info.appbundleIdentifier + ".AppBackupDidFinish")

    static let importAppDeepLinkURLKey = "fileURL"
    static let appBackupResultKey = "result"
    static let addSourceDeepLinkURLKey = "sourceURL"
}
