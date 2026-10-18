# SideSign Authentication.swift - SideInstaller GSA parity patch

### Apply to: Mu3242-Scripter/SideSign -. Sources/DeveloperPortal/Authentication.swift

### In sendAuthenticationRequest, replace the headers block with:

```swift
        // SideInstaller base_headers parity
        let headers: [String: String] = [
            "Content-Type": "text/x-xml-plist",
            "Accept": "text/x-xml-plist",
            "X-MMe-Client-Info": anisetteData.clientInfo,
            "User-Agent": h.grandSlam.userAgent,
            "X-Xcode-Version": "14.2 (14C18)",
            "X-Apple-App-Info": "com.apple.gs.xcode.auth",
            "Connection": "close"
        ]
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let allHeaders = request.allHTTPHeaderFields {
            verboseLog("[SideSign] sendAuthenticationRequest HTTP headers: \(prettyJSONString(from: sanitizeHeadersForLogging(allHeaders)))")
        }

        // SideInstaller: retry HTTP 429 with spaced backoff (RETRY_429_DELAYS style)
        let retryDelays: [UInt64] = [2_000_000_000, 5_000_000_000] // 2s, 5s nanoseconds
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
                debugLog("[SideSign] GrandSlam HTTP 429 — retrying in \(delay / 1_000_000_000)s (attempt \(attempt + 1))")
                try await Task.sleep(nanoseconds: delay)
                attempt += 1
                continue
            }
            break
        }
```

### Then continue with existing code (starting from `guard !data.isEmpty`...)

### After patching, update SideStore submodule:
Clone SideStore, run:
```bash
git submodule set-url Dependencies/SideSign https://github.com/Mr3242-Scripter/SideSign.git
git submodule update --init Dependencies/SideSign
cd Dependencies/SideSign && git checkout main && git pull
git add Dependencies/SideSign
cd ../.. && git commit -m "chore: bump SideSign submodule to Windows GSA patch" && git push
```
