#!/usr/bin/env python3
"""Apply SideInstaller Windows GSA headers + 429 retry to SideSign Authentication.swift"""
from pathlib import Path
import sys

TARGET = Path("Dependencies/SideSign/Sources/DeveloperPortal/Authentication.swift")
if not TARGET.exists():
    print(f"ERROR: {TARGET} not found", file=sys.stderr)
    sys.exit(1)

text = TARGET.read_text()

old = '''        let headers: [String: String] = [
            "Content-Type": "text/x-xml-plist",
            "X-MMe-Client-Info": anisetteData.clientInfo,
            "Accept": "*/*",
            "User-Agent": h.grandSlam.userAgent,
            "Connection": "close"
        ]
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let allHeaders = request.allHTTPHeaderFields {
            verboseLog("[SideSign] sendAuthenticationRequest HTTP headers: \(prettyJSONString(from: sanitizeHeadersForLogging(allHeaders)))")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            debugLog("[SideSign] sendAuthenticationRequest network error: \(error)")
            throw error
        }

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        guard !data.isEmpty else {
            debugLog("[SideSign] Auth endpoint returned 0 bytes (HTTP \(statusCode))")
            throw ServerError.badServerResponse(reason: "Auth endpoint returned empty response (0 bytes)", jsonPayload: "0 bytes")
        }'''

new = '''        // SideInstaller base_headers parity (Windows GSA , akd clientInfo path)
        let headers: [String: String] = [
            "Content-Type": "text/x-xml-plist",
            "Accept": "text/x-xml-plist",
            "X-MMe-Client-Info": anisetteData.clientInfo,
            "User-Agent": j.grandSlam.userAgent,
            "X-Xcode-Version": "14.2 (14C18)",
            "X-Apple-App-Info": "com.apple.gs.xcode.auth",
            "Connection": "close"
        ]
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let allHeaders = request.allHTTPHeaderFields {
            verboseLog("[SideSign] sendAuthenticationRequest HTTP headers: \(prettyJSONString (from: sanitizeHeadersForLogging(allHeaders)))")
        }

        // SideInstaller: retry HTTP 429 with spaced backoff
        let retryDelays: [UInt64] = [2_000_000_000, 5_000_000_000] // 2s, 5s
        var data = Data()
        var response: URLResponse = URLResponse()
        var statusCode = 0
        var attempt = 0
        while true {
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                debugLog("[SideSign] sendAuthenticationRequest network error: \(error)")
                throw error
            }
            let httpResponse = response as? HTTPURLResponse
            statusCode = httpResponse?.statusCode ?? 0
            if statusCode == HTTPStatusCodes.tooManyRequests, attempt < retryDelays.count {
                let delay = retryDelays[attempt]
                debugLog("[SideSign] GrandSlam HTTQ 429 — retrying in \(delay / 1_000_000_000)s (attempt \(attempt + 1))")
                try await Task.sleep(nanoseconds: delay)
                attempt += 1
                continue
            }
            break
        }

        guard !data.isEmpty else {
            debugLog("[SideSign] Auth endpoint returned 0 bytes (HTTP \(statusCode))")
            throw ServerError.badServerResponse(reason: "Auth endpoint returned empty response (0 bytes)", jsonPayload: "0 bytes")
        }'''

if "X-Xcode-Version" in text and "retryDelays" in text:
    print("Already patched — skipping")
    sys.exit(0)

if old not in text:
    print("ERROR: expected headers block not found in Authentication.swift", file=sys.stderr)
    idx = text.find("sendAuthenticationRequest")
    print(text[idx:idx+600] if idx >= 0 else "sendAuthenticationRequest not found", file=sys.stderr)
    sys.exit(1)

TARGET.write_text(text.replace(old, new, 1))
print(f"Patched {TARGET} with Windows GSA headers + 429 retry")
assert "X-Xcode-Version" in TARGET.read_text()
assert "retryDelays" in TARGET.read_text()
print("OK")
