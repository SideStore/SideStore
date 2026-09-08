//
//  TVWebFileTransferManager.swift
//  SideStore
//
//  Created by Magesh K on 26/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

#if os(tvOS)
@preconcurrency import UIKit
import Foundation
import Network
import Darwin
import UniformTypeIdentifiers

public final class TVWebFileTransferManager: @unchecked Sendable {
    public static let shared = TVWebFileTransferManager()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "io.sidestore.TVWebFileTransferManager", qos: .userInitiated)
    private var activeAlert: UIAlertController?

    private enum Mode {
        case `import`(title: String, acceptedExtensions: [String], completion: (URL?) -> Void)
        case export(fileURL: URL, title: String, completion: (() -> Void)?)
    }
    private var currentMode: Mode?

    private init() {}

    public func startImport(
        contentTypes: [UTType]? = nil,
        acceptedExtensions: [String] = [],
        title: String = "Import File",
        presentingVC: UIViewController,
        completion: @escaping (URL?) -> Void
    ) {
        self.stop()

        var extensions = acceptedExtensions
        if let contentTypes = contentTypes {
            for type in contentTypes {
                if let ext = type.preferredFilenameExtension {
                    extensions.append(ext)
                }
            }
        }
        if extensions.isEmpty {
            extensions = ["ipa", "sideconf", "json", "mobiledevicepairing", "plist", "zip"]
        }

        self.currentMode = .import(title: title, acceptedExtensions: extensions, completion: completion)

        guard let serverURL = self.startListener() else {
            debugLog("[TVWebFileTransferManager] Failed to start listener for import")
            completion(nil)
            return
        }

        DispatchQueue.main.async{
            let alert = UIAlertController(
                title: title,
                message: String(format: NSLocalizedString("Open this URL on your iPhone, iPad, or Mac on the same Wi-Fi network to upload:\n\n%@", comment: ""), serverURL),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
                self?.stop()
                completion(nil)
            })

            self.activeAlert = alert
            presentingVC.present(alert, animated: true)
        }
    }

    public func startExport(
        fileURL: URL,
        title: String = "Export File",
        presentingVC: UIViewController,
        completion: (() -> Void)? = nil
    ) {
        self.stop()
        self.currentMode = .export(fileURL: fileURL, title: title, completion: completion)

        guard let serverURL = self.startListener() else {
            debugLog("[TVWebFileTransferManager] Failed to start listener for export")
            completion?()
            return
        }

        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: title,
                message: String(format: NSLocalizedString("Open this URL on your iPhone, iPad, or Mac on the same Wi-Fi network to download '%@':\n\n%@", comment: ""), fileURL.lastPathComponent, serverURL),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("Done", comment: ""), style: .default) { [weak self] _ in
                self?.stop()
                completion?()
            })

            self.activeAlert = alert
            presentingVC.present(alert, animated: true)
        }
    }

    public func stop() {
        self.listener?.cancel()
        self.listener = nil
        self.currentMode = nil

        DispatchQueue.main.async { [weak self] in
            self?.activeAlert?.dismiss(animated: true)
            self?.activeAlert = nil
        }
    }

    private func startListener(port: UInt16 = AppConstants.WebTransferServer.defaultPort) -> String? {
        do {
            let params = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            let listener = try NWListener(using: params, on: nwPort)

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    debugLog("[TVWebFileTransferManager] Server listening on port \(port)")
                case .failed(let error):
                    debugLog("[TVWebFileTransferManager] Server failed: \(error)")
                default:
                    break
                }
            }

            listener.start(queue: self.queue)
            self.listener = listener

            if let ip = self.getLocalIPAddress() {
                return "http://\(ip):\(port)"
            }
            return "http://localhost:\(port)"
        } catch {
            debugLog("[TVWebFileTransferManager] Failed to start NWListener: \(error)")
            return nil
        }
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
                    self.handleGETRequest(connection: connection)
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

    private func handleGETRequest(connection: NWConnection) {
        switch self.currentMode {
        case .import(let title, let acceptedExtensions, _):
            let acceptAttr = acceptedExtensions.map { ".\($0)" }.joined(separator: ",")
            self.sendHTMLResponse(connection: connection, body: self.makeUploadHTMLPage(title: title, acceptAttr: acceptAttr))
        case .export(let fileURL, let title, _):
            do {
                let fileData = try Data(contentsOf: fileURL)
                let filename = fileURL.lastPathComponent
                let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"\(filename)\"\r\nContent-Length: \(fileData.count)\r\nConnection: close\r\n\r\n"
                var responseData = Data(header.utf8)
                responseData.append(fileData)
                connection.send(content: responseData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } catch {
                self.sendHTMLResponse(connection: connection, body: self.makeErrorHTMLPage("Failed to read export file: \(error.localizedDescription)"), statusCode: 500)
            }
        case .none:
            self.sendHTMLResponse(connection: connection, body: self.makeErrorHTMLPage("No active transfer."), statusCode: 404)
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
        guard case .import(_, _, let completion) = self.currentMode else {
            self.sendHTMLResponse(connection: connection, body: self.makeErrorHTMLPage("No active import session."))
            return
        }

        let rawString = String(data: bodyData, encoding: .utf8) ?? String(data: bodyData, encoding: .isoLatin1) ?? ""
        var fileData: Data = bodyData
        var filename = "uploaded_file"

        // Multipart parsing
        if let filenameRange = rawString.range(of: "filename=\"") {
            let rest = rawString[filenameRange.upperBound...]
            if let quoteEnd = rest.range(of: "\"") {
                filename = String(rest[..<quoteEnd.lowerBound])
            }
        }

        if let bodyStartRange = bodyData.range(of: Data("\r\n\r\n".utf8)) {
            let actualBody = bodyData.subdata(in: bodyStartRange.upperBound..<bodyData.count)
            if let boundaryEndRange = actualBody.range(of: Data("\r\n--".utf8), options: .backwards) {
                fileData = actualBody.subdata(in: 0..<boundaryEndRange.lowerBound)
            } else {
                fileData = actualBody
            }
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try fileData.write(to: tempURL)
            self.sendHTMLResponse(connection: connection, body: self.makeSuccessHTMLPage(filename: filename))

            DispatchQueue.main.async { [weak self] in
                self?.activeAlert?.dismiss(animated: true)
                self?.activeAlert = nil
                self?.stop()
                completion(tempURL)
            }
        } catch {
            self.sendHTMLResponse(connection: connection, body: self.makeErrorHTMLPage("Failed to save uploaded file: \(error.localizedDescription)"))
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

    private func makeUploadHTMLPage(title: String, acceptAttr: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title) - SideStore Apple TV</title>
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
                <h1>\(title)</h1>
                <p>Select and upload your file to Apple TV.</p>
                <form action="/upload" method="post" enctype="multipart/form-data">
                    <div class="upload-box">
                        <input type="file" name="file" accept="\(acceptAttr)" required>
                    </div>
                    <button type="submit">Upload to Apple TV</button>
                </form>
            </div>
        </body>
        </html>
        """
    }

    private func makeSuccessHTMLPage(filename: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Transfer Successful</title>
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
                <h1>✓ Upload Successful</h1>
                <p><code>\(filename)</code> has been transferred to Apple TV.<br>SideStore will now continue automatically.</p>
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
            <title>Transfer Error</title>
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
                <h1>Transfer Failed</h1>
                <p>\(message)</p>
                <p><a href="/">Try Again</a></p>
            </div>
        </body>
        </html>
        """
    }
}
#endif
