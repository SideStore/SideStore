//
//  OperationError.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign
import AltStoreCore
import minimuxer

extension OperationError
{
    enum Code: Int, ALTErrorCode, CaseIterable {
        typealias Error = OperationError
        
        // General
        case unknown = 1000
        case unknownResult = 1001
//        case cancelled = 1002
        case timedOut = 1003
        case notAuthenticated = 1004
        case appNotFound = 1005
        case unknownUDID = 1006
        case invalidApp = 1007
        case invalidParameters = 1008
        case maximumAppIDLimitReached = 1009
        case noSources = 1010
        case openAppFailed = 1011
        case missingAppGroup = 1012
        case forbidden = 1013
        case sourceNotAdded = 1014


        // Connection
        
        /* Connection */
        case serverNotFound = 1200
        case connectionFailed = 1201
        case connectionDropped = 1202
        
        /* Pledges */
        case pledgeRequired = 1401
        case pledgeInactive = 1402

        /* SideStore Only */
        case unableToConnectSideJIT
        case unableToRespondSideJITDevice
        case wrongSideJITIP
        case SideJITIssue // (error: String)
        case refreshsidejit
        case refreshAppFailed
        case tooNewError
        case anisetteV1Error//(message: String)
        case provisioningError//(result: String, message: String?)
        case anisetteV3Error//(message: String)
        case cacheClearError//(errors: [String])
        case noWiFi
        
        case invalidOperationContext
    }
    
    static var cancelled: CancellationError { CancellationError() }
    
    static let unknownResult: OperationError = .init(code: .unknownResult)
    static let timedOut: OperationError = .init(code: .timedOut)
    static let unableToConnectSideJIT: OperationError = .init(code: .unableToConnectSideJIT)
    static let unableToRespondSideJITDevice: OperationError = .init(code: .unableToRespondSideJITDevice)
    static let wrongSideJITIP: OperationError = .init(code: .wrongSideJITIP)
    static let notAuthenticated: OperationError = .init(code: .notAuthenticated)
    static let unknownUDID: OperationError = .init(code: .unknownUDID)
    static let invalidApp: OperationError = .init(code: .invalidApp)
    static let noSources: OperationError = .init(code: .noSources)
    static let missingAppGroup: OperationError = .init(code: .missingAppGroup)
    
    static let noWiFi: OperationError = .init(code: .noWiFi)
    static let tooNewError: OperationError = .init(code: .tooNewError)
    static let provisioningError: OperationError = .init(code: .provisioningError)
    static let anisetteV1Error: OperationError = .init(code: .anisetteV1Error)
    static let anisetteV3Error: OperationError = .init(code: .anisetteV3Error)
    
    static let cacheClearError: OperationError = .init(code: .cacheClearError)

    static func unknown(failureReason: String? = nil, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .unknown, failureReason: failureReason, sourceFile: file, sourceLine: line)
    }

    static func appNotFound(name: String?) -> OperationError {
        OperationError(code: .appNotFound, appName: name)
    }

    static func openAppFailed(name: String?) -> OperationError {
        OperationError(code: .openAppFailed, appName: name)
    }
    static let domain = OperationError(code: .unknown)._domain
    
    static func SideJITIssue(error: String?) -> OperationError {
        var o = OperationError(code: .SideJITIssue)
        o.errorFailure = error
        return o
    }
    
    static func maximumAppIDLimitReached(appName: String, requiredAppIDs: Int, availableAppIDs: Int, expirationDate: Date) -> OperationError {
        OperationError(code: .maximumAppIDLimitReached, appName: appName, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
    }

    static func provisioningError(result: String, message: String?) -> OperationError {
        var o = OperationError(code: .provisioningError, failureReason: result)
        o.errorTitle = message
        return o
    }

    static func cacheClearError(errors: [String]) -> OperationError {
        OperationError(code: .cacheClearError, failureReason: errors.joined(separator: "\n"))
    }

    static func anisetteV1Error(message: String) -> OperationError {
        OperationError(code: .anisetteV1Error, failureReason: message)
    }

    static func anisetteV3Error(message: String) -> OperationError {
        OperationError(code: .anisetteV3Error, failureReason: message)
    }

    static func refreshAppFailed(message: String) -> OperationError {
        OperationError(code: .refreshAppFailed, failureReason: message)
    }

    static func invalidParameters(_ message: String? = nil) -> OperationError {
        OperationError(code: .invalidParameters, failureReason: message)
    }
    
    static func invalidOperationContext(_ message: String? = nil) -> OperationError {
        OperationError(code: .invalidOperationContext, failureReason: message)
    }
    
    static func forbidden(failureReason: String? = nil, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .forbidden, failureReason: failureReason, sourceFile: file, sourceLine: line)
    }
    
    static func sourceNotAdded(@Managed _ source: Source, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .sourceNotAdded, sourceName: $source.name, sourceFile: file, sourceLine: line)
    }
    
    static func pledgeRequired(appName: String, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .pledgeRequired, appName: appName, sourceFile: file, sourceLine: line)
    }
    
    static func pledgeInactive(appName: String, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .pledgeInactive, appName: appName, sourceFile: file, sourceLine: line)
    }
}


struct OperationError: ALTLocalizedError {

    let code: Code

    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue
    var appName: String?
    
    @UserInfoValue
    var sourceName: String?
    
    var requiredAppIDs: Int?
    var availableAppIDs: Int?
    var expirationDate: Date?

    var sourceFile: String?
    var sourceLine: UInt?

    private var _failureReason: String?

    private init(code: Code, failureReason: String? = nil,
                 appName: String? = nil, sourceName: String? = nil, requiredAppIDs: Int? = nil,
                 availableAppIDs: Int? = nil, expirationDate: Date? = nil, sourceFile: String? = nil, sourceLine: UInt? = nil){
        self.code = code
        self._failureReason = failureReason

        self.appName = appName
        self.sourceName = sourceName
        self.requiredAppIDs = requiredAppIDs
        self.availableAppIDs = availableAppIDs
        self.expirationDate = expirationDate
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }

    var errorFailureReason: String {
        switch self.code {
        case .unknown:
            var failureReason = self._failureReason ?? NSLocalizedString("发生了未知错误。", comment: "")
            guard let sourceFile, let sourceLine else { return failureReason }
            failureReason += " (\(sourceFile) 行 \(sourceLine))"
            return failureReason
        case .unknownResult: return NSLocalizedString("操作返回了未知结果。", comment: "")
        case .timedOut: return NSLocalizedString("操作超时。", comment: "")
        case .notAuthenticated: return NSLocalizedString("您未登录。", comment: "")
        case .unknownUDID: return NSLocalizedString("SideStore 无法确定此设备的 UDID。", comment: "")
        case .invalidApp: return NSLocalizedString("该应用格式无效。", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("在 7 天内无法注册超过 10 个 App ID。", comment: "")
        case .noSources: return NSLocalizedString("没有 AppFlex 源。", comment: "")
        case .missingAppGroup: return NSLocalizedString("无法访问 AppFlex 的共享应用组。", comment: "")
        case .forbidden:
            guard let failureReason = self._failureReason else { return NSLocalizedString("操作被禁止。", comment: "") }
            return failureReason
            
        case .sourceNotAdded:
            let sourceName = self.sourceName.map { String(format: NSLocalizedString("源 “%@”", comment: ""), $0) } ?? NSLocalizedString("该源", comment: "")
            return String(format: NSLocalizedString("%@ 没有添加到 AppFlex。", comment: ""), sourceName)

        case .appNotFound:
            let appName = self.appName ?? NSLocalizedString("该应用", comment: "")
            return String(format: NSLocalizedString("%@ 未找到。", comment: ""), appName)
        case .openAppFailed:
            let appName = self.appName ?? NSLocalizedString("该应用", comment: "")
            return String(format: NSLocalizedString("AppFlex 被拒绝启动 %@。", comment: ""), appName)
        case .noWiFi: return NSLocalizedString("您似乎未连接到 WiFi 和/或 WireGuard VPN！\n没有 WiFi 和 WireGuard VPN，AppFlex 永远无法安装或刷新应用程序。", comment: "")
        case .tooNewError: return NSLocalizedString("iOS 17 更改了 JIT 的启用方式，因此 SideStore 目前无法在没有 SideJITServer 的情况下启用它，抱歉给您带来的不便。\n我们会在有解决方案时通知大家！", comment: "")
        case .unableToConnectSideJIT: return NSLocalizedString("无法连接到 AppFlexJITServer，请检查您是否在同一 Wi-Fi 网络上，并确保防火墙已正确设置。", comment: "")
        case .unableToRespondSideJITDevice: return NSLocalizedString("AppFlexJITServer 无法连接到您的 iDevice，请确保您已通过 'SideJITServer -y' 配对您的设备，或尝试从设置中刷新 AppFlexJITServer。", comment: "")
        case .wrongSideJITIP: return NSLocalizedString("AppFlexJITServer IP 不正确，请确保您与 AppFlexJITServer 在同一 Wi-Fi 网络上。", comment: "")
        case .refreshsidejit: return NSLocalizedString("无法找到应用，请尝试从设置中刷新 AppFlexJITServer。", comment: "")
        case .anisetteV1Error: return NSLocalizedString("从 V1 服务器获取 AppFlex 数据时发生错误：%@。请尝试使用其他 AppFlex 服务器。", comment: "")
        case .provisioningError: return NSLocalizedString("配置时发生错误：%@ %@。请重试。如果问题持续，请在 GitHub Issues 上报告！", comment: "")
        case .anisetteV3Error: return NSLocalizedString("从 V3 服务器获取 AppFlex 数据时发生错误：%@。请重试。如果问题持续，请在 AppFlex官网 上报告！", comment: "")
        case .cacheClearError: return NSLocalizedString("清除缓存时发生错误：%@", comment: "")
        case .SideJITIssue: return NSLocalizedString("使用 AppFlexJIT 时发生错误：%@", comment: "")
            
        case .refreshAppFailed:
            let message = self._failureReason ?? ""
            return String(format: NSLocalizedString("无法刷新应用\n%@", comment: ""), message)

        case .invalidParameters:
            let message = self._failureReason.map { ": \n\($0)" } ?? "."
            return String(format: NSLocalizedString("无效的参数%@", comment: ""), message)
        case .invalidOperationContext:
            let message = self._failureReason.map { ": \n\($0)" } ?? "."
            return String(format: NSLocalizedString("无效的操作上下文%@", comment: ""), message)
        case .serverNotFound: return NSLocalizedString("找不到 AltServer。", comment: "")
        case .connectionFailed: return NSLocalizedString("无法建立与 AltServer 的连接。", comment: "")
        case .connectionDropped: return NSLocalizedString("与 AltServer 的连接已断开。", comment: "")
            
        case .pledgeRequired:
            let appName = self.appName ?? NSLocalizedString("此应用", comment: "")
            return String(format: NSLocalizedString("%@ 需要一个有效的承诺才能安装。", comment: ""), appName)
            
        case .pledgeInactive:
            let appName = self.appName ?? NSLocalizedString("该应用", comment: "")
            return String(format: NSLocalizedString("您的承诺已不再有效。请续订以继续正常使用 %@。", comment: ""), appName)
        }
    }
    var recoverySuggestion: String? {
        switch self.code
        {
        case .noWiFi: return NSLocalizedString("确保 VPN 已打开并且您已连接到任意 WiFi 网络！", comment: "")
        case .serverNotFound: return NSLocalizedString("确保您与运行 AltServer 的计算机在同一 Wi-Fi 网络上，或者尝试通过 USB 将设备连接到计算机。", comment: "")
        case .maximumAppIDLimitReached:
            let baseMessage = NSLocalizedString("删除侧载应用以释放 App ID 插槽。", comment: "")
            guard let appName, let requiredAppIDs, let availableAppIDs, let expirationDate else { return baseMessage }
            var message: String

            if requiredAppIDs > 1
            {
                let availableText: String
                
                switch availableAppIDs
                {
                case 0: availableText = NSLocalizedString("没有可用的 App ID", comment: "")
                case 1: availableText = NSLocalizedString("仅剩 1 个可用", comment: "")
                default: availableText = String(format: NSLocalizedString("仅剩 %@ 个可用", comment: ""), NSNumber(value: availableAppIDs))
                }
                
                let prefixMessage = String(format: NSLocalizedString("%@ 需要 %@ 个 App ID，但 %@。", comment: ""), appName, NSNumber(value: requiredAppIDs), availableText)
                message = prefixMessage + " " + baseMessage + "\n\n"
            }
            else
            {
                message = baseMessage + " "
            }

            let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: expirationDate)
            let dateFormatter = DateComponentsFormatter()
            dateFormatter.maximumUnitCount = 1
            dateFormatter.unitsStyle = .full

            let remainingTime = dateFormatter.string(from: dateComponents)!

            message += String(format: NSLocalizedString("您可以在 %@ 后注册另一个 App ID。", comment: ""), remainingTime)

            return message
            
        default: return nil
        }
    }
}

extension MinimuxerError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .NoDevice:
            return NSLocalizedString("无法从 muxer 获取设备", comment: "")
        case .NoConnection:
            return NSLocalizedString("无法连接到设备，请确保 Wireguard 已启用并且您已连接到 WiFi。这可能意味着配对无效。", comment: "")
        case .PairingFile:
            return NSLocalizedString("无效的配对文件。您的配对文件要么没有 UDID，要么不是有效的 plist 文件。请使用 jitterbugpair 来生成它", comment: "")
            
        case .CreateDebug:
            return self.createService(name: "debug")
        case .LookupApps:
            return self.getFromDevice(name: "installed apps")
        case .FindApp:
            return self.getFromDevice(name: "path to the app")
        case .BundlePath:
            return self.getFromDevice(name: "bundle path")
        case .MaxPacket:
            return self.setArgument(name: "max packet")
        case .WorkingDirectory:
            return self.setArgument(name: "working directory")
        case .Argv:
            return self.setArgument(name: "argv")
        case .LaunchSuccess:
            return self.getFromDevice(name: "launch success")
        case .Detach:
            return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .Attach:
            return NSLocalizedString("Unable to attach to the app's process", comment: "")
            
        case .CreateInstproxy:
            return self.createService(name: "instproxy")
        case .CreateAfc:
            return self.createService(name: "AFC")
        case .RwAfc:
            return NSLocalizedString("AFC 无法管理设备上的文件。这通常意味着配对无效。", comment: "")
        case .InstallApp(let message):
            return NSLocalizedString("无法安装应用：\(message.toString())", comment: "")
        case .UninstallApp:
            return NSLocalizedString("无法卸载应用", comment: "")

        case .CreateMisagent:
            return self.createService(name: "misagent")
        case .ProfileInstall:
            return NSLocalizedString("无法管理设备上的配置文件", comment: "")
        case .ProfileRemove:
            return NSLocalizedString("无法管理设备上的配置文件", comment: "")
        }
    }
    
    fileprivate func createService(name: String) -> String {
        return String(format: NSLocalizedString("无法在设备上启动 %@ 服务器。", comment: ""), name)
    }

    fileprivate func getFromDevice(name: String) -> String {
        return String(format: NSLocalizedString("无法从设备获取 %@。", comment: ""), name)
    }

    fileprivate func setArgument(name: String) -> String {
        return String(format: NSLocalizedString("无法在设备上设置 %@。", comment: ""), name)
    }
}
