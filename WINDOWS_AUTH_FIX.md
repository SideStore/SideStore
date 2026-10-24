# Temporary Mac auth fix (SideInstaller v1.6.1 style)

Apple started rejecting Windows/Android anisette data after the verification code
with error -80046 ("This action cannot be completed at this time").

This branch now forces the working SideInstaller defaults:

1. On-device anisette OFF (users can still toggle it)
2. Auto-rotation OFF by default
3. Default anisette server: SideStore (New) / Mac servers first
4. Client-info reports a current Mac (not the old macOS 10.12 string that triggers -23782)
5. Clean adi.pb on first sign-in after the change so Apple issues a fresh identity

Previous Windows client-info / win.ani.sidestore.io defaults are removed because
Apple now fails the final sign-in step with them.
