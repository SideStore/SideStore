//
//  PairingWebUploadServer.swift
//  SideStore
//
//  Created by Magesh K on 26/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

#if os(tvOS)
import Foundation
import Network
import Darwin

public final class PairingWebUploadServer: @unchecked Sendable {
    public static let shared = PairingWebUploadServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "io.sidestore.PairingWebUploadServer", qos: .userInitiated)
    private var onUploadSuccess: ((String) -> Void)?
    public private(set) var port: UInt16 = AppConstants.PairingWebServer.defaultPort

    private init() {}

    public func start(preferredPort: UInt16 = AppConstants.PairingWebServer.defaultPort, onUploadSuccess: @escaping (String) -> Void) -> String? {
        self.stop()
        self.onUploadSuccess = onUploadSuccess
        self.port = preferredPort

        do {
            let params = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: preferredPort) ?? .any
            let listener = try NWListener(using: params, on: nwPort)

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    debugLog("[PairingWebServer] Server listening on port \(preferredPort)")
                case .failed(let error):
                    debugLog("[PairingWebServer] Server failed with error: \(error)")
                default:
                    break
                }
            }

            listener.start(queue: self.queue)
            self.listener = listener

            if let ip = self.getLocalIPAddress() {
                return "http://\(ip):\(preferredPort)"
            }
            return "http://localhost:\(preferredPort)"
        } catch {
            debugLog("[PairingWebServer] Failed to start NWListener: \(error)")
            return nil
        }
    }

    public func stop() {
        self.listener?.cancel()
        self.listener = nil
        self.onUploadSuccess = nil
    }

    public func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) else { continue }
            guard addr.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let name = String(cString: ptr.pointee.ifa_name)
                if name == "en0" || name == "en1" {
                    return String(cString: hostname)
                } else if address == nil {
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: self.queue)
        self.readRequest(connection: connection, accumulatedData: Data())
    }

    private func readRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            var currentData = accumulatedData
            if let data = data, !data.isEmpty {
                currentData.append(data)
            }

            if let requestString = String(data: currentData, encoding: .utf8) ?? String(data: currentData, encoding: .isoLatin1) {
                if requestString.hasPrefix("GET ") {
                    self.sendHTMLResponse(connection: connection, body: self.makeUploadHTMLPage())
                    return
                } else if requestString.hasPrefix("POST ") {
                    if let contentLength = self.extractContentLength(from: requestString),
                       let headerEndRange = currentData.range(of: Data("\r\n\r\n".utf8)) {
                        let headerLength = headerEndRange.upperBound
                        let totalExpectedLength = headerLength + contentLength
                        if currentData.count < totalExpectedLength && !isComplete {
                            self.readRequest(connection: connection, accumulatedData: currentData)
                            return
                        }

                        let bodyData = currentData.subdata(in: headerLength..<currentData.count)
                        self.processUploadedBody(bodyData: bodyData, connection: connection)
                        return
                    }
                }
            }

            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.readRequest(connection: connection, accumulatedData: currentData)
            }
        }
    }

    private func extractContentLength(from headers: String) -> Int? {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(valStr)
            }
        }
        return nil
    }

    private func processUploadedBody(bodyData: Data, connection: NWConnection) {
        let rawString = String(data: bodyData, encoding: .utf8) ?? String(data: bodyData, encoding: .isoLatin1) ?? ""
        var pairingFileString: String?

        if rawString.contains("<?xml") || rawString.contains("<plist") {
            if let startRange = rawString.range(of: "<?xml") ?? rawString.range(of: "<plist"),
               let endRange = rawString.range(of: "</plist>", options: .backwards) {
                pairingFileString = String(rawString[startRange.lowerBound..<endRange.upperBound])
            }
        } else {
            pairingFileString = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let pairingFileString = pairingFileString, !pairingFileString.isEmpty {
            self.sendHTMLResponse(connection: connection, body: self.makeSuccessHTMLPage())
            DispatchQueue.main.async { [weak self] in
                self?.onUploadSuccess?(pairingFileString)
            }
        } else {
            self.sendHTMLResponse(connection: connection, body: self.makeErrorHTMLPage("Could not parse a valid pairing file (.mobiledevicepairing)."))
        }
    }

    private func sendHTMLResponse(connection: NWConnection, body: String, statusCode: Int = 200) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(statusCode) OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func makeUploadHTMLPage() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>SideStore Apple TV Pairing</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #121212;
                    color: #FFFFFF;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                    padding: 20px;
                    box-sizing: border-box;
                }
                .card {
                    background-color: #1E1E1E;
                    border-radius: 18px;
                    padding: 32px;
                    max-width: 440px;
                    width: 100%;
                    box-shadow: 0 8px 32px rgba(0,0,0,0.5);
                    text-align: center;
                }
                h1 {
                    font-size: 24px;
                    font-weight: 700;
                    margin-bottom: 8px;
                    color: #FF5A5F;
                }
                p {
                    color: #AAAAAA;
                    font-size: 15px;
                    line-height: 1.5;
                    margin-bottom: 24px;
                }
                .upload-box {
                    border: 2px dashed #333333;
                    border-radius: 12px;
                    padding: 24px 16px;
                    margin-bottom: 24px;
                    background: #181818;
                }
                input[type="file"] {
                    display: block;
                    width: 100%;
                    color: #EEEEEE;
                    font-size: 14px;
                    margin-bottom: 12px;
                }
                button {
                    background-color: #FF5A5F;
                    color: white;
                    border: none;
                    border-radius: 12px;
                    padding: 14px 28px;
                    font-size: 16px;
                    font-weight: 600;
                    cursor: pointer;
                    width: 100%;
                    transition: opacity 0.2s;
                }
                button:hover {
                    opacity: 0.9;
                }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>SideStore Pairing</h1>
                <p>Upload your <code>ALTPairingFile.mobiledevicepairing</code> to pair your Apple TV.</p>
                <form action="/upload" method="post" enctype="multipart/form-data">
                    <div class="upload-box">
                        <input type="file" name="pairingFile" accept=".mobiledevicepairing,.plist,.xml" required>
                    </div>
                    <button type="submit">Upload Pairing File</button>
                </form>
            </div>
        </body>
        </html>
        """
    }

    private func makeSuccessHTMLPage() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Pairing Successful</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #121212;
                    color: #FFFFFF;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                }
                .card {
                    background-color: #1E1E1E;
                    border-radius: 18px;
                    padding: 32px;
                    max-width: 400px;
                    text-align: center;
                    box-shadow: 0 8px 32px rgba(0,0,0,0.5);
                }
                h1 { color: #4CD964; margin-bottom: 12px; }
                p { color: #AAAAAA; font-size: 15px; line-height: 1.5; }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>✓ Pairing Successful</h1>
                <p>Your pairing file has been saved to Apple TV.<br>SideStore will now continue automatically.</p>
            </div>
        </body>
        </html>
        """
    }

    private func makeErrorHTMLPage(_ message: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <title>Upload Error</title>
            <style>
                body { font-family: -apple-system, sans-serif; background: #121212; color: #FFF; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
                .card { background: #1E1E1E; border-radius: 18px; padding: 32px; text-align: center; max-width: 400px; }
                h1 { color: #FF3B30; }
                p { color: #AAA; }
                a { color: #FF5A5F; text-decoration: none; }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>Upload Failed</h1>
                <p>\(message)</p>
                <p><a href="/">Try Again</a></p>
            </div>
        </body>
        </html>
        """
    }
}
#endif
