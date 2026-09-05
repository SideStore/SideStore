//
//  AppConstants.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/7/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
import SideSign


public enum AppConstants {
    // features required for functioning
    public static let mandatoryFeatures: Set<ALTFeature> = [
        .appGroups
    ]

    enum Proxy {
        static let address = "127.0.0.1"
        static let port = "51820"
        static let defaultPort: UInt16 = 51820
        static let serverURL = "\(address):\(port)"
    }
    
    public enum Connection {
        //fix: temporarily reverting the no default overrideIP 
        //     coz though our auto discovery works perfectly, 
        //     localDevVPN is flawed in its routing table 
        //   - so until it is fixed, to reduce friction we are okay with this
        //
        // when localdevvpn is fixed, we can comment out the line with an IP with with the one with ""
        public static let defaultOverrideIP = "10.7.0.1"
        // public static let defaultOverrideIP = ""    // auto-discover is robust we dont need to supply default
        public static let defaultRemoteServerIP = "10.7.0.1"
    }
    
    public enum Sources {
        public static let fetchTimeout: TimeInterval = 3.0
    }
    
    public enum Bonjour {
        public static let defaultDomain = "local."
        public static let defaultDiscoveryTimeout: TimeInterval = 2.0
        public static let periodicRefreshInterval: TimeInterval = 6.0
    }
    
    public enum SideJIT {
        public static let bonjourServiceName = "SideJITServer"
        public static let bonjourServiceType = "_http._tcp"
        public static let timeout: TimeInterval = 2.0
        public static let defaultServerURL = "http://\(bonjourServiceName).\(bonjourServiceType).local:8080".lowercased()
    }
    
    public enum WebTransferServer {
        public static let defaultPort: UInt16 = 8080
    }
    public typealias PairingWebServer = WebTransferServer

    public enum Anisette {
        public static let hiddenBaseDirectoryName = ".anisette"
        public static let appSupportSubdirectory = "SideStore"
        public static let defaultDeviceSerialNumber = "0"
        public static let defaultODAMetadataURL = "https://zzz.haus/oda.json"
        public static let defaultClientInfo = "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.dt.Xcode/26.0)>"
        public static let defaultUserAgent = "AuthKit/1 (Macintosh; OS X 26.6) (com.apple.dt.Xcode/26.0)"
    }

    public enum Pairing {
        public static let bundleResourceName = "ALTPairingFile"
        public static let fileExtension = "mobiledevicepairing"
        public static let fileName = "\(bundleResourceName).\(fileExtension)"
        public static let placeholderString = "insert pairing file here"
    }

    public enum Shortcuts {
        public static let turnOffDataURL = URL(string: "shortcuts://run-shortcut?name=TurnOffData")!
        public static let turnOnDataURL  = URL(string: "shortcuts://run-shortcut?name=TurnOnData")!
    }

    public enum Installation {
        public static let selfInstallSuspendDelayNs: UInt64 = 500_000_000
    }

    public static let pairingFileName = Pairing.fileName
    public static let accountConfigurationFileName = "Account.sideconf"
}
