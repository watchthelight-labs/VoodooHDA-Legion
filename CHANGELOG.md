# Changelog

## 3.7.0-legion.1 (2026-10-17)

- First published version of the patch and build script. The built kext has been the audio driver on a Legion 5 15IAX10 running macOS 26.7.1 since 2026-10-16: internal speakers and volume working, internal microphone detected.
- `legion.patch`: personality `LayoutId` before the PCI `layout-id`, mixer bound checks, `setMath` null check.
- Build script: VoodooHDA LE from the audited upstream commit `beb415a`, `IOPCIMatch 0x7f508086`, HDMI personality removed, `LayoutId 18`.
