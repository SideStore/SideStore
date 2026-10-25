# SideInstaller 1.6.1 full parity — files to apply

Copy these into your repos:

## SideSign (`Mr3242-Scripter/SideSign`)
- `Authentication.swift` → `Sources/DeveloperPortal/Authentication.swift`
  - Forces current Mac (`Mac15,7` / macOS 27) on GrandSlam (fixes **-80046**)
  - Trusted-device 2FA first; SMS/iCloud 403 → devices
  - Soft-fail trusted-device 403 so a code can still be entered

## SideStore (`Mr3242-Scripter/SideStore`)
- `AppConstants.swift` → `SideStore/AppConstants.swift`
  - Default server: `https://new.ani.sidestore.io` (SideStore New)
  - `macADIOrder`, `macClientInfo` matching SideInstaller
- `AnisetteProvider.swift` → `SideStore/Core/Anisette/AnisetteProvider.swift`
  - Mac servers first (SideStore New → jkcoxson → iLoader → …)
  - Always reports SideInstaller `MAC_CLIENT_INFO` (not server’s macOS 10.12)
  - ODA forced off; rotation defaulted off; Windows host cleared
- `AnisetteServerList.swift` → `AltStore/Settings/AnisetteServerList.swift`
  - **“SideInstaller Auto (Mac ADI)” toggle at the top** of Anisette Servers
  - When ON: ODA off, rotation off, SideStore New selected, adi.pb cleared
- `AppBootManager.swift` → `SideStore/AppBootManager.swift` (already has migration)

## After rebuild on device
1. Confirm **SideInstaller Auto (Mac ADI)** is ON (top of Anisette Servers)
2. **Reset adi.pb** with “Keep header customizations” **unticked**
3. Sign in (Apple will ask for a code once more — expected)

## Why -80046 was still happening
Remote anisette servers still advertise **macOS 10.12**. SideInstaller **overrides** that with a **current Mac**. Using the server’s string after the verification code causes -80046.
