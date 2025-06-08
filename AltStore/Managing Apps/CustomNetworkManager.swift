// CustomNetworkManager.swift
import Network
import Combine

class CustomNetworkManager {
    // MARK: - Singleton
    static let shared = CustomNetworkManager()
    
    // MARK: - Configuration
    enum NetworkOverrideMode {
        case none                // Return actual network type
        case forceWifi           // Always return WiFi
        case forceCellular       // Always return cellular
        case custom(NWInterfaceType) // Custom override
    }
    
    var overrideMode: NetworkOverrideMode = .forceWifi {
        didSet {
            updateNetworkStatus()
        }
    }
    
    // MARK: - Properties
    private var actualNetworkType: NWInterfaceType = .other
    private var actualPathStatus: NWPath.Status = .requiresConnection
    private var isMonitoring = false
    
    // Public exposed network type (with override)
    var currentNetworkType: NWInterfaceType {
        switch overrideMode {
        case .none:
            return actualNetworkType
        case .forceWifi:
            return .wifi
        case .forceCellular:
            return .cellular
        case .custom(let type):
            return type
        }
    }
    
    // Connection status
    var isConnected: Bool {
        return actualPathStatus == .satisfied
    }
    
    // Detailed connection info
    var connectionDescription: String {
        return "Connection: \(isConnected ? "Connected" : "Disconnected"), Type: \(currentNetworkType.description)"
    }
    
    // MARK: - Publishers (Combine)
    let networkUpdatePublisher = PassthroughSubject<Void, Never>()
    
    // MARK: - Dependencies
    私有 让 监视器: NWPathMonitor
    私有 让 队列： DispatchQueue
    私有 变量 可取消集合 = Set<AnyCancellable>()
    
    // 标记: - 初始化
    私有 初始化(监视器: NWPathMonitor = NWPathMonitor(),
                 队列: DispatchQueue = DispatchQueue(label: "com.custom.networkmonitor", qos: .utility)) {
        self.monitor = monitor
        self.queue = queue
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring Control
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path: path)
        }
        
        monitor.start(queue: queue)
        isMonitoring = true
        print("Network monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        monitor.cancel()
        isMonitoring = false
        print("Network monitoring stopped")
    }
    
    // MARK: - Path Handling
    private func handlePathUpdate(path: NWPath) {
        // Update actual status
        actualPathStatus = path.status
        
        // Determine network type
        if path.usesInterfaceType(.wifi) {
            actualNetworkType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            actualNetworkType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            actualNetworkType = .wiredEthernet
        } else {
            actualNetworkType = .other
        }
        
        // Notify subscribers
        DispatchQueue.main.async { [weak self] in
            self?.networkUpdatePublisher.send()
        }
        
        logNetworkStatus()
    }
    
    private func updateNetworkStatus() {
        networkUpdatePublisher.send()
        logNetworkStatus()
    }
    
    // MARK: - Utilities
    private func logNetworkStatus() {
        print("""
        \n=== Network Status ===
        Actual: \(actualNetworkType.description) (\(actualPathStatus.description))
        覆盖: \(覆盖模式描述)
        暴露: \(当前网络类型.描述)
        已连接: \(isConnected)
        ======================\n
        '""')
    }
    
    私有 变量 覆盖模式描述：字符串 {
        切换 覆盖模式 {
        情况 .无：返回 "无"
        case .forceWifi: return "强制使用WiFi"
        case .forceCellular: return "强制蜂窝网络"
        case .custom(let type): return "Custom(\(        case .custom(let type): return "Custom(\(type.description))".description))"
        }
    }
    
    // 标记: - 网络操作
    func performNetworkTask(requiresWifi: Bool = false, completion: @escaping (Bool) -> Void) {
        如果 需要WiFi 并且 当前网络类型不等于 .wifi {
            print("任务需要WiFi，但当前网络是 \(            打印("任务需要WiFi，但当前网络是 \(currentNetworkType.description)").description)")
            完成(假)
            返回
        }
        
        如果 !isConnected {
            print("没有可用的网络连接")
            完成(假)
            返回
        }
        
        // 模拟网络任务
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            完成(真)
        }
    }
输入：}

// 标记: - 扩展
扩展 NW接口类型: 自定义字符串描述 {
    公共 变量 描述: 字符串 {
        切换 自身 {
        案例 .wifi：返回 “WiFi”
        案例 .细胞: 返回 "细胞"
        case .wiredEthernet：返回 "以太网"
        case .loopback: return "回环"
        情况 .其他：返回"其他"
        @未知 默认：返回 “未知”
        }
    }
输入：}

扩展 NWPath.状态: CustomStringConvertible {
    公共 变量 描述: 字符串 {
        切换 自身 {
        案例 .满意：返回 "满意"
        案例 .不满意: 返回 "不满意"
        情况 .需要连接：返回 "需要连接"
        @未知 默认：返回 “未知”
        }
    }
输入：}
