//
//  AppConstants.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/7/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
import SideSign
import Minimuxer

public enum AppConstants {
    // features required for functioning
    public static let mandatoryFeatures: Set<ALTFeature> = [
        .appGroups
    ]

    public enum Proxy {
        public static let address             = MinimuxerConstants.empServerHost
        public static let defaultPort: UInt16 = MinimuxerConstants.empServerPort
        public static let port                = String(defaultPort)
        public static let serverURL           = "\(address):\(port)"
    }
    
    public enum Connection {
        public static let defaultOverrideIP     = "10.7.0.1"
        public static let defaultRemoteServerIP = "10.7.0.1"
    }
    
    public enum Sources {
        public static let fetchTimeout: TimeInterval  = 3.0
        public static let defaultSourcesURL           = URL(string: "https://sidestore.io/default-sources")!
        public static let sideStoreCommunitySourceURL = URL(string: "https://sidestore.io/apps-v2.json/")!
        public static let sideStoreFallbackIconURL    = URL(string: "https://sidestore.io/apps-v2.json/apps/sidestore/icon.png")!
        public static let sideStoreWebsite            = URL(string: "https://sidestore.io")!
    }
    
    public enum Bonjour {
        public static let defaultDomain                         = "local."
        public static let defaultDiscoveryTimeout: TimeInterval = 2.0
        public static let periodicRefreshInterval: TimeInterval = 6.0
    }
    
    public enum SideJIT {
        public static let bonjourServiceName    = "SideJITServer"
        public static let bonjourServiceType    = "_http._tcp"
        public static let timeout: TimeInterval = 2.0
        public static let defaultServerURL      = "http://\(bonjourServiceName).\(bonjourServiceType).local:8080".lowercased()
    }
    
    public enum WebTransferServer {
        public static let defaultPort: UInt16 = 8080
    }
    public typealias PairingWebServer = WebTransferServer

    public enum Anisette {
        public static let hiddenBaseDirectoryName     = ".anisette"
        public static let appSupportSubdirectory      = "SideStore"
        public static let defaultDeviceSerialNumber   = "0"
        public static let defaultODAMetadataURL       = URL(string: "https://zzz.haus/oda.json")!
        public static var defaultODAMetadataURLString: String { defaultODAMetadataURL.absoluteString }

        // Proxied from upstream SideSign
        public static let defaultClientInfo           = Constants.Anisette.defaultClientInfo
        public static let defaultUserAgent            = Constants.Anisette.defaultUserAgent

        public enum URLs {
            public static let grandSlamLookup = Constants.Anisette.URLs.grandSlamLookup
        }

        public enum Headers {
            public static let machineID        = Constants.Anisette.Headers.machineID
            public static let oneTimePassword  = Constants.Anisette.Headers.oneTimePassword
            public static let localUserID      = Constants.Anisette.Headers.localUserID
            public static let routingInfo      = Constants.Anisette.Headers.routingInfo
            public static let deviceID         = Constants.Anisette.Headers.deviceID
            public static let serialNumber     = Constants.Anisette.Headers.serialNumber
            public static let clientInfo       = Constants.Anisette.Headers.clientInfo
            public static let userAgent        = Constants.Anisette.Headers.userAgent
            public static let clientTime       = Constants.Anisette.Headers.clientTime
            public static let locale           = Constants.Anisette.Headers.locale
            public static let timeZone         = Constants.Anisette.Headers.timeZone
        }

        public enum Libraries {
            public static let requiredNames = Constants.Anisette.Libraries.requiredNames
        }

        public enum Servers {
            public static let defaultSource        = "https://servers.sidestore.io/servers.json"
            public static let defaultServerURL     = "https://ani.sidestore.io"
            public static let connectivityCheckURL = URL(string: "https://www.apple.com/library/test/success.html")!
        }

        public static let remoteCacheDuration     = Constants.Anisette.remoteCacheDuration
        public static let serverValidationTimeout = Constants.Anisette.serverValidationTimeout
        public static let remoteRequestTimeout    = Constants.Anisette.remoteRequestTimeout
    }

    public enum GrandSlam {
        public static let service        = Constants.GrandSlam.service
        public static let headerVersion  = Constants.GrandSlam.headerVersion
        public static let authApp        = Constants.GrandSlam.authApp
        public static let userAgent      = Constants.GrandSlam.userAgent
    }

    public enum AppleAuth {
        public static let appIDKey   = Constants.AppleAuth.appIDKey
        public static let userAgent  = Constants.AppleAuth.userAgent
    }

    public enum DeveloperServices {
        public static let clientID                = Constants.DeveloperServices.clientID
        public static let protocolVersion         = Constants.DeveloperServices.protocolVersion
        public static let servicesProtocolVersion = Constants.DeveloperServices.servicesProtocolVersion
        public static let userAgent               = Constants.DeveloperServices.userAgent
    }

    public enum URLs {
        // Proxied upstream URLs from SideSign
        public static let developerAccount          = Constants.URLs.developerAccount
        public static let developerServicesBase     = Constants.URLs.developerServicesBase
        public static let developerServicesV1Base   = Constants.URLs.developerServicesV1Base
        public static let grandSlamAuth             = Constants.URLs.grandSlamAuth
        public static let grandSlamValidate         = Constants.URLs.grandSlamValidate
        public static let trustedDevice             = Constants.URLs.trustedDevice
        public static let appleAuthDevices          = Constants.URLs.appleAuthDevices
        public static let appleAccount              = URL(string: "https://account.apple.com")!

        // SideStore Documentation & Community URLs
        public static let pairingDocumentation      = URL(string: "https://docs.sidestore.io/docs/advanced/pairing-file")!
        public static let errorCodesDocumentation   = URL(string: "https://docs.sidestore.io/docs/troubleshooting/error-codes")!
        public static let sideStoreWebsite          = URL(string: "https://sidestore.io")!
        public static let sideStoreGitHub           = URL(string: "https://github.com/SideStore")!
        public static let sideStoreIssues           = URL(string: "https://github.com/SideStore/SideStore/issues")!
        public static let sideStoreDiscord          = URL(string: "https://discord.gg/sidestore-949183273383395328")!
    }

    public enum Minimuxer {
        public static let remotePairingPort                     = MinimuxerConstants.remotePairingPort
        public static let lockdowndPort                         = MinimuxerConstants.lockdowndPort
        public static let defaultTCPProbeTimeoutMs              = MinimuxerConstants.defaultTCPProbeTimeoutMs
        public static let empServerHost                         = MinimuxerConstants.empServerHost
        public static let empServerPort                         = MinimuxerConstants.empServerPort
        public static let defaultHostName                       = MinimuxerConstants.defaultHostName
        public static let defaultHostModel                      = MinimuxerConstants.defaultHostModel
        public static let remotePairingDaemonServiceType        = MinimuxerConstants.remotePairingDaemonServiceType
        public static let remotePairingPairableHostServiceType  = MinimuxerConstants.remotePairingPairableHostServiceType
        public static let remotePairingManualPairingServiceType = MinimuxerConstants.remotePairingManualPairingServiceType
        public static let vpnHandshakeTimeoutNs                 = MinimuxerConstants.vpnHandshakeTimeoutNs
    }

    public enum Pairing {
        public static let bundleResourceName = "ALTPairingFile"
        public static let fileExtension      = "mobiledevicepairing"
        public static let fileName           = "\(bundleResourceName).\(fileExtension)"
        public static let placeholderString  = "insert pairing file here"
        public static let documentationURL   = AppConstants.URLs.pairingDocumentation
    }

    public enum Shortcuts {
        public static let turnOffDataURL = URL(string: "shortcuts://run-shortcut?name=TurnOffData")!
        public static let turnOnDataURL  = URL(string: "shortcuts://run-shortcut?name=TurnOnData")!
    }

    public enum Installation {
        public static let selfInstallSuspendDelayNs: UInt64 = 500_000_000
    }

    public static let pairingFileName              = Pairing.fileName
    public static let accountConfigurationFileName = "Account.sideconf"
    public static let defaultAccountRepairMessage  = Constants.defaultAccountRepairMessage

    public typealias HTTPStatusCodes            = SideSign.HTTPStatusCodes
    public typealias GrandSlamAuthErrorCodes    = SideSign.GrandSlamAuthErrorCodes
    public typealias DeveloperPortalResultCodes = SideSign.DeveloperPortalResultCodes
    public typealias UIDeviceFamilyCodes        = SideSign.UIDeviceFamilyCodes
}
