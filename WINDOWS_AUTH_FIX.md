# Full SideInstaller 1.6.1 anisette fix (parity)

Apple rejects Windows/Android anisette after the verification code with
error -80046 ("This action cannot be completed at this time").

This branch implements **exactly** what SideInstaller 1.6.1 does for sign-in
and what it applies to SideStore after install:

## Runtime (AnisetteProvider)
1. On-Device Anisette forced OFF
2. Auto-rotation defaulted OFF
3. Mac anisette servers first (`ani.sidestore.io` / SideStore New, then other Mac hosts)
4. Client-info / User-Agent from the Mac server's `/v3/client_info` (current Mac)
5. Purge adi.pb on ADI errors including -80046
6. Windows ADI hosts last-resort only

## One-shot boot migration (AppBootManager) — same as SideInstaller post-install
Runs once (`AnisetteMacADI.sideInstallerParity.v1`):
1. `useOnDeviceAnisette = false`
2. `disableAnisetteRotation = true`
3. `menuAnisetteURL = https://ani.sidestore.io` (SideStore New)
4. Clear Windows/Android client-info overrides (`customAnisetteClientInfo` / User-Agent → defaults)
5. Purge stored `adi.pb` so Apple issues a fresh Mac identity (verification code asked once more)

Files:
- `SideStore/Core/Anisette/AnisetteProvider.swift`
- `SideStore/AppBootManager.swift`
- `SideStore/AppConstants.swift`

After building this branch, first sign-in may request the 2FA code again. That is expected and matches SideInstaller.
