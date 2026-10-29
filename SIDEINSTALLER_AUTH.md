# Full SideInstaller authentication parity (SideSign)

This is not a one-line “fix”. SideSign’s `Authentication.swift` now follows SideInstaller’s **LoginState** machine from `apple_account.rs`.

## State machine (2FA)

| SideInstaller state | Behavior |
|---------------------|----------|
| `NeedsDevice2FA` | GET trusted-device code (soft-fail OK) |
| `NeedsDevice2FAVerification` | Prompt for device code; verify |
| `NeedsSMS2FA(id)` | PUT JSON phone; on refuse → `NeedsDevice2FA` |
| `NeedsSMS2FAVerification(id)` | Prompt for SMS code; verify; refuse → devices |
| Success | Return → caller does **NeedsLogin** (login again) |

## Always on (SideInstaller 1.6.1)

- `CURRENT_MAC` = MacBookPro18,3 / macOS 26.6 for Mac ADI servers
- `MAC_CLIENT_INFO` = Mac15,7 only on bare 403 auth-page retry
- Minimal 2FA headers (Device-Id, MD, MD-M, RINFO, Identity-Token)
- Fresh OTP before verify + before login again (`adi.pb` when present)
- Never show “Could not connect to iCloud” (PHONE_CODE_REFUSED → devices)
- Fresh TCP connection per GSA request

## Files

1. SideSign `Sources/DeveloperPortal/Authentication.swift`
2. SideSign `Sources/Models/Errors.swift` (sanitize iCloud display)
3. SideStore `SideStore/Core/Anisette/AnisetteProvider.swift` (Mac servers + adi blob for OTP refresh)

## How to test once

1. Rebuild SideSign (macOS CI green) + SideStore with matching submodule
2. ODA off, rotation off
3. Server: `https://new.ani.sidestore.io` or `https://mac-ani.jkcoxson.com`
4. Reset adi.pb once
5. One sign-in

If SMS is refused, enter the **device** code — same as SideInstaller.
