# Temporary Mac auth fix (SideInstaller v1.6.1 full parity)

Apple rejects Windows/Android anisette after the verification code with
error -80046 ("This action cannot be completed at this time").

This branch implements the same behaviour SideInstaller 1.6.1 applies:

1. **On-Device Anisette forced OFF** (it now ends in -80046).
2. **Auto-rotation defaulted OFF** so the app stays on a working Mac server.
3. **Mac anisette servers first**: `ani.sidestore.io` (SideStore New),
   `mac-ani.jkcoxson.com`, etc. Windows ADI hosts are last-resort only.
4. **Client-info / User-Agent** come from the Mac server's `/v3/client_info`
   (current Mac), not a hard-coded Windows or ancient macOS 10.12 string.
5. **One-time purge of adi.pb** so Apple issues a fresh Mac identity
   (you will be asked for the verification code once more).

Files touched:
- `SideStore/Core/Anisette/AnisetteProvider.swift` — full Mac-first logic
- `SideStore/AppConstants.swift` — default server URLs point at Mac hosts

After building this branch, the first sign-in may request the 2FA code again.
That is expected and matches SideInstaller.
