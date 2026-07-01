//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CommonCrypto
import Starscream
import AltStoreCore
import AltSign

class ANISETTE_VERBOSITY: Operation {} // dummy tag iface

@objc(FetchAnisetteDataOperation)
final class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, WebSocketDelegate {
    let context: OperationContext
    var socket: WebSocket!
    
    var url: URL?
    var startProvisioningURL: URL?
    var endProvisioningURL: URL?
    
    var clientInfo: String?
    var userAgent: String?
    
    var mdLu: String?
    var deviceId: String?
    
    init(context: OperationContext) {
        self.context = context
    }
    
    override func main() {
        super.main()
        
        if let error = self.context.error {
            self.finish(.failure(error))
            return
        }
        
        // TODO: Pass in proper view context to show the Toast messages
        let viewContext = context.presentingViewController
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let urlString = try await self.getAnisetteServerUrl(viewContext)

                // set as preferred
                UserDefaults.standard.menuAnisetteURL = urlString
                let url = URL(string: urlString)
                self.url = url
                self.verboseLog("Anisette URL: \(self.url!.absoluteString)")

                if let identifier = Keychain.shared.identifier,
                   let adiPb = Keychain.shared.adiPb {
                    try await self.fetchAnisetteV3(identifier, adiPb)
                } else {
                    try await self.provision()
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    

    private func getAnisetteServerUrl(_ viewContext: UIViewController?) async throws -> String {
        let serverUrls = UserDefaults.standard.menuAnisetteServersList
        guard !serverUrls.isEmpty else {
            throw NSError(domain: "AnisetteError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No anisette servers configured."])
        }

        let lastServer = UserDefaults.standard.menuAnisetteURL
        let startIndex = serverUrls.firstIndex(of: lastServer) ?? 0
        
        for triedCount in 0..<serverUrls.count {
            let currentIndex = (startIndex + triedCount) % serverUrls.count
            let currentServerUrlString = serverUrls[currentIndex]

            guard let url = URL(string: currentServerUrlString) else {
                let errmsg = "Skipping invalid URL: \(currentServerUrlString)"
                self.verboseLog(errmsg)
                showToast(viewContext: viewContext, message: errmsg)
                continue
            }

            let success = try await pingServer(url)
            if success {
                let okmsg = "Found working server: \(url.absoluteString)"
                self.verboseLog(okmsg)
                if triedCount > 0 {
                    self.showToast(viewContext: viewContext, message: okmsg)
                }
                UserDefaults.standard.menuAnisetteURL = url.absoluteString
                return url.absoluteString
            } else {
                let errmsg = "Failed to reach server: \(url.absoluteString), trying next server."
                self.verboseLog(errmsg)
                self.showToast(viewContext: viewContext, message: errmsg)
            }
        }

        // Loop exhausted: Save the next index to cycle uniformly
        let nextIndex = (startIndex + 1) % serverUrls.count
        UserDefaults.standard.menuAnisetteURL = serverUrls[nextIndex]

        throw NSError(domain: "AnisetteError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No valid server found."])
    }
    
    private func showToast(viewContext: UIViewController?, message: String) {
        if let viewContext = viewContext {
            let error = OperationError.anisetteV1Error(message: message)
            let toastView = ToastView(error: error)
//            toastView.textLabel.textColor = .altPrimary
//            toastView.detailTextLabel.textColor = .altPrimary
            Task { @MainActor in
                toastView.show(in: viewContext)
            }
        }
    }

    private func pingServer(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10 // Timeout after 10 seconds
        
        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode
        
        guard let statusCode = statusCode,
              (200...299).contains(statusCode) else {
            return false
        }
        
        return true
    }
    
    
    // MARK: - COMMON
    
    func extractAnisetteData(_ data: Data, _ response: HTTPURLResponse?, v3: Bool) throws {
        // make sure this JSON is in the format we expect
        // convert data to json
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
            if v3 {
                if json["result"] == "GetHeadersError" {
                    let message = json["message"]
                    self.verboseLog("Error getting V3 headers: \(message ?? "no message")")
                    if let message = message,
                       message.contains("-45061") {
                        self.verboseLog("Error message contains -45061 (not provisioned), resetting adi.pb and retrying")
                        Keychain.shared.adiPb = nil
                        Task {
                            do {
                                try await provision()
                            } catch {
                                self.finish(.failure(error))
                            }
                        }
                        return
                    } else { throw OperationError.anisetteV3Error(message: message ?? "Unknown error") }
                }
            }
            
            // try to read out a dictionary
            // for some reason serial number isn't needed but it doesn't work unless it has a value
            var formattedJSON: [String: String] = ["deviceSerialNumber": "0"]
            if let machineID = json["X-Apple-I-MD-M"] { formattedJSON["machineID"] = machineID }
            if let oneTimePassword = json["X-Apple-I-MD"] { formattedJSON["oneTimePassword"] = oneTimePassword }
            if let routingInfo = json["X-Apple-I-MD-RINFO"] { formattedJSON["routingInfo"] = routingInfo }
            
            if v3 {
                formattedJSON["deviceDescription"] = self.clientInfo!
                formattedJSON["localUserID"] = self.mdLu!
                formattedJSON["deviceUniqueIdentifier"] = self.deviceId!
                
                // Generate date stuff on client
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = TimeZone.init(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                let dateString = formatter.string(from: Date())
                formattedJSON["date"] = dateString
                formattedJSON["locale"] = Locale.current.identifier
                formattedJSON["timeZone"] = TimeZone.current.abbreviation()
            } else {
                if let deviceDescription = json["X-MMe-Client-Info"] { formattedJSON["deviceDescription"] = deviceDescription }
                if let localUserID = json["X-Apple-I-MD-LU"] { formattedJSON["localUserID"] = localUserID }
                if let deviceUniqueIdentifier = json["X-Mme-Device-Id"] { formattedJSON["deviceUniqueIdentifier"] = deviceUniqueIdentifier }
                
                if let date = json["X-Apple-I-Client-Time"] { formattedJSON["date"] = date }
                if let locale = json["X-Apple-Locale"] { formattedJSON["locale"] = locale }
                if let timeZone = json["X-Apple-I-TimeZone"] { formattedJSON["timeZone"] = timeZone }
            }
            
            if let response = response,
               let version = response.value(forHTTPHeaderField: "Implementation-Version") {
                self.verboseLog("Implementation-Version: \(version)")
            } else { self.verboseLog("No Implementation-Version header") }
            
            self.verboseLog("Anisette used: \(formattedJSON)")
            self.verboseLog("Original JSON: \(json)")
            if let anisette = ALTAnisetteData(json: formattedJSON) {
                self.debugLog("Anisette is valid!")
                self.finish(.success(anisette))
            } else {
                self.debugLog("Anisette is invalid!!!!")
                if v3 {
                    throw OperationError.anisetteV3Error(message: "Invalid anisette (the returned data may not have all the required fields)")
                } else {
                    throw OperationError.anisetteV1Error(message: "Invalid anisette (the returned data may not have all the required fields)")
                }
            }
        } else {
            if v3 {
                throw OperationError.anisetteV3Error(message: "Invalid anisette (the returned data may not be in JSON)")
            } else {
                throw OperationError.anisetteV1Error(message: "Invalid anisette (the returned data may not be in JSON)")
            }
        }
    }
    
    // MARK: - V1
    private func handleV1() async throws {
        self.verboseLog("Server is V1")
        
        if UserDefaults.shared.trustedServerURL == AnisetteManager.currentURLString {
            self.verboseLog("Server has already been trusted, fetching anisette")
            try await self.fetchAnisetteV1()
            return
        }
        
        self.debugLog("Alerting user about outdated server")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let alert = UIAlertController(title: "WARNING: Outdated anisette server", message: "We've detected you are using an older anisette server. Using this server has a higher likelihood of locking your account and causing other issues. Are you sure you want to continue?", preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "Continue", style: UIAlertAction.Style.destructive, handler: { action in
                self.verboseLog("Fetching anisette via V1")
                UserDefaults.shared.trustedServerURL = AnisetteManager.currentURLString
                Task {
                    do {
                        try await self.fetchAnisetteV1()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { action in
                self.debugLog("Cancelled anisette operation")
                continuation.resume(throwing: OperationError.cancelled)
            }))
     
            let keyWindow = UIApplication.shared.windows.filter { $0.isKeyWindow }.first
     
            Task { @MainActor in
                if let presentingController = keyWindow?.rootViewController?.presentedViewController {
                    presentingController.present(alert, animated: true)
                } else {
                    keyWindow?.rootViewController?.present(alert, animated: true)
                }
            }
        }
    }
    
    private func fetchAnisetteV1() async throws {
        self.verboseLog("Fetching anisette V1")
        let (data, response) = try await URLSession.shared.data(from: self.url!)
        try self.extractAnisetteData(data, response as? HTTPURLResponse, v3: false)
    }
    
    // MARK: - V3: PROVISIONING
    
    private func provision() async throws {
        try await fetchClientInfo()
        self.verboseLog("Getting provisioning URLs")
        var request = self.buildAppleRequest(url: URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!)
        request.httpMethod = "GET"
        
        let (data, _) = try await URLSession.shared.data(for: request)
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Dictionary<String, Dictionary<String, Any>>,
           let startProvisioningString = plist["urls"]?["midStartProvisioning"] as? String,
           let startProvisioningURL = URL(string: startProvisioningString),
           let endProvisioningString = plist["urls"]?["midFinishProvisioning"] as? String,
           let endProvisioningURL = URL(string: endProvisioningString) {
            self.startProvisioningURL = startProvisioningURL
            self.endProvisioningURL = endProvisioningURL
            self.verboseLog("startProvisioningURL: \(self.startProvisioningURL!.absoluteString)")
            self.verboseLog("endProvisioningURL: \(self.endProvisioningURL!.absoluteString)")
            self.verboseLog("Starting a provisioning session")
            self.startProvisioningSession()
        } else {
            self.debugLog("Apple didn't give valid URLs! Got response: \(String(data: data, encoding: .utf8) ?? "not utf8")")
            throw OperationError.provisioningError(result: "Apple didn't give valid URLs. Please try again later", message: nil)
        }
    }
    
    func startProvisioningSession() {
        let provisioningSessionURL = self.url!.appendingPathComponent("v3").appendingPathComponent("provisioning_session")
        var wsRequest = URLRequest(url: provisioningSessionURL)
        wsRequest.timeoutInterval = 5
        self.socket = WebSocket(request: wsRequest)
        self.socket.delegate = self
        self.socket.connect()
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .text(let string):
            self.handleTextEvent(string, client: client)
            
        case .connected:
            self.debugLog("Connected")
            
        case .disconnected(let string, let code):
            self.debugLog("Disconnected: \(code); \(string)")
            
        case .error(let error):
            self.debugLog("Got error: \(String(describing: error))")
            
        default:
            self.debugLog("Unknown event: \(event)")
        }
    }
    
    private func handleTextEvent(_ string: String, client: WebSocketClient) {
        do {
            if let json = try JSONSerialization.jsonObject(with: string.data(using: .utf8)!, options: []) as? [String: Any] {
                guard let result = json["result"] as? String else {
                    self.debugLog("The server didn't give us a result")
                    client.disconnect(closeCode: 0)
                    self.finish(.failure(OperationError.provisioningError(result: "The server didn't give us a result", message: nil)))
                    return
                }
                self.verboseLog("Received result: \(result)")
                switch result {
                case "GiveIdentifier":
                    self.verboseLog("Giving identifier")
                    client.json(["identifier": Keychain.shared.identifier!])
                    
                case "GiveStartProvisioningData":
                    self.handleGiveStartProvisioningData(client: client)
                    
                case "GiveEndProvisioningData":
                    self.handleGiveEndProvisioningData(json: json, client: client)
                    
                case "ProvisioningSuccess":
                    self.handleProvisioningSuccess(json: json, client: client)
                    
                default:
                    if result.contains("Error") || result.contains("Invalid") || result == "ClosingPerRequest" || result == "Timeout" || result == "TextOnly" {
                        self.debugLog("Failing because of \(result)")
                        self.finish(.failure(OperationError.provisioningError(result: result, message: json["message"] as? String)))
                    }
                }
            }
        } catch let error as NSError {
            self.debugLog("Failed to handle text: \(error.localizedDescription)")
            self.finish(.failure(OperationError.provisioningError(result: error.localizedDescription, message: nil)))
        }
    }
    
    private func handleGiveStartProvisioningData(client: WebSocketClient) {
        self.verboseLog("Getting start provisioning data")
        let body = [
            "Header": [String: Any](),
            "Request": [String: Any](),
        ]
        var request = self.buildAppleRequest(url: self.startProvisioningURL!)
        request.httpMethod = "POST"
        request.httpBody = try! PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Dictionary<String, Dictionary<String, Any>>,
                   let spim = plist["Response"]?["spim"] as? String {
                    self.verboseLog("Giving start provisioning data")
                    client.json(["spim": spim])
                } else {
                    self.debugLog("Apple didn't give valid start provisioning data! Got response: \(String(data: data, encoding: .utf8) ?? "not utf8")")
                    client.disconnect(closeCode: 0)
                    self.finish(.failure(OperationError.provisioningError(result: "Apple didn't give valid start provisioning data. Please try again later", message: nil)))
                }
            } catch {
                client.disconnect(closeCode: 0)
                self.finish(.failure(error))
            }
        }
    }
    
    private func handleGiveEndProvisioningData(json: [String: Any], client: WebSocketClient) {
        self.verboseLog("Getting end provisioning data")
        guard let cpim = json["cpim"] as? String else {
            self.debugLog("The server didn't give us a cpim")
            client.disconnect(closeCode: 0)
            self.finish(.failure(OperationError.provisioningError(result: "The server didn't give us a cpim", message: nil)))
            return
        }
        let body = [
            "Header": [String: Any](),
            "Request": [
                "cpim": cpim,
            ],
        ]
        var request = self.buildAppleRequest(url: self.endProvisioningURL!)
        request.httpMethod = "POST"
        request.httpBody = try! PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Dictionary<String, Dictionary<String, Any>>,
                   let ptm = plist["Response"]?["ptm"] as? String,
                   let tk = plist["Response"]?["tk"] as? String {
                    self.verboseLog("Giving end provisioning data")
                    client.json(["ptm": ptm, "tk": tk])
                } else {
                    self.debugLog("Apple didn't give valid end provisioning data! Got response: \(String(data: data, encoding: .utf8) ?? "not utf8")")
                    client.disconnect(closeCode: 0)
                    self.finish(.failure(OperationError.provisioningError(result: "Apple didn't give valid end provisioning data. Please try again later", message: nil)))
                }
            } catch {
                client.disconnect(closeCode: 0)
                self.finish(.failure(error))
            }
        }
    }
    
    private func handleProvisioningSuccess(json: [String: Any], client: WebSocketClient) {
        self.debugLog("Provisioning succeeded!")
        client.disconnect(closeCode: 0)
        guard let adiPb = json["adi_pb"] as? String else {
            self.debugLog("The server didn't give us an adi.pb file")
            self.finish(.failure(OperationError.provisioningError(result: "The server didn't give us an adi.pb file", message: nil)))
            return
        }
        Keychain.shared.adiPb = adiPb
        Task {
            do {
                try await self.fetchAnisetteV3(Keychain.shared.identifier!, Keychain.shared.adiPb!)
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    func buildAppleRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(self.clientInfo!, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(self.userAgent!, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        request.setValue(self.mdLu!, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(self.deviceId!, forHTTPHeaderField: "X-Mme-Device-Id")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let dateString = formatter.string(from: Date())
        request.setValue(dateString, forHTTPHeaderField: "X-Apple-I-Client-Time")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation(), forHTTPHeaderField: "X-Apple-I-TimeZone")
        return request
    }
    
    // MARK: - V3: FETCHING
    
    private func fetchClientInfo() async throws {
        if self.clientInfo != nil &&
           self.userAgent != nil &&
           self.mdLu != nil &&
           self.deviceId != nil &&
           Keychain.shared.identifier != nil {
            self.verboseLog("Skipping client_info fetch since all the properties we need aren't nil")
            return
        }
        self.verboseLog("Trying to get client_info")
        let clientInfoURL = self.url!.appendingPathComponent("v3").appendingPathComponent("client_info")
        
        let (data, _) = try await URLSession.shared.data(from: clientInfoURL)
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
            if let clientInfo = json["client_info"] {
                self.verboseLog("Server is V3")
                
                self.clientInfo = clientInfo
                self.userAgent = json["user_agent"]!
                self.verboseLog("Client-Info: \(self.clientInfo!)")
                self.verboseLog("User-Agent: \(self.userAgent!)")
                
                if Keychain.shared.identifier == nil {
                    self.verboseLog("Generating identifier")
                    var bytes = [Int8](repeating: 0, count: 16)
                    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                    
                    if status != errSecSuccess {
                        self.debugLog("ERROR GENERATING IDENTIFIER!!! \(status)")
                        throw OperationError.provisioningError(result: "Couldn't generate identifier", message: nil)
                    }
                    
                    Keychain.shared.identifier = Data(bytes: &bytes, count: bytes.count).base64EncodedString()
                }
                
                let decoded = Data(base64Encoded: Keychain.shared.identifier!)!
                self.mdLu = decoded.sha256().hexEncodedString()
                self.verboseLog("X-Apple-I-MD-LU: \(self.mdLu!)")
                let uuid: UUID = decoded.object()
                self.deviceId = uuid.uuidString.uppercased()
                self.verboseLog("X-Mme-Device-Id: \(self.deviceId!)")
            } else {
                try await self.handleV1()
            }
        } else {
            throw OperationError.anisetteV3Error(message: "Couldn't fetch client info. The returned data may not be in JSON")
        }
    }
    
    private func fetchAnisetteV3(_ identifier: String, _ adiPb: String) async throws {
        try await self.fetchClientInfo()
        self.verboseLog("Fetching anisette V3")
        var request = URLRequest(url: self.url!.appendingPathComponent("v3").appendingPathComponent("get_headers"))
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: [
            "identifier": identifier,
            "adi_pb": adiPb
        ], options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try self.extractAnisetteData(data, response as? HTTPURLResponse, v3: true)
    }
    
    
    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: ANISETTE_VERBOSITY.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}

extension WebSocketClient {
    func json(_ dictionary: [String: String]) {
        let data = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
        self.write(string: String(data: data, encoding: .utf8)!)
    }
}

extension Data {
    // https://stackoverflow.com/a/25391020
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
    
    // https://stackoverflow.com/a/40089462
    func hexEncodedString() -> String {
        return self.map { String(format: "%02hhX", $0) }.joined()
    }
    
    // https://stackoverflow.com/a/59127761
    func object<T>() -> T { self.withUnsafeBytes { $0.load(as: T.self) } }
}
