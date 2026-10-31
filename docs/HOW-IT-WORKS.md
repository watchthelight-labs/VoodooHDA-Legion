# How WTLAudio works

## Why not AppleALC

On macOS Sequoia the ALC257 in the Legion 5 15IAX10 works with AppleALC 1.9.8 and `alcid=18`: AppleALC patches AppleHDA to accept the codec and carries a pin configuration (layout 18, originally for the Legion Y540) that maps the speakers and the internal microphone. That proved the HDA link to the codec works even though the `8086:7F50` controller advertises itself as an audio DSP (PCI class 0x0401) rather than a plain HDA controller (0x0403).

macOS Tahoe 26 ships no AppleHDA.kext. AppleALC has nothing to patch, and the codec has no driver. The options are to bring AppleHDA back by root patching (what OpenCore Legacy Patcher does) or to use a driver that does not depend on it.

## VoodooHDA

VoodooHDA is a port of FreeBSD's `snd_hda` to IOKit, maintained by the Clover team. It maps the controller's BARs, runs the CORB/RIRB verb interface to the codec, parses the widget graph, and publishes IOAudioEngine and IOAudioStream objects so CoreAudio sees outputs and inputs. It has two build variants:

- `BL`: Apple's IOAudioFamily 740.1 source compiled into the kext, so OpenCore can inject it anywhere. On Tahoe that would register IOAudioEngine, IOAudioStream and the other class names a second time next to the real IOAudioFamily (still in the kernel collection, used by USB audio and HDMI audio), and whichever loads second fails.
- `LE`: links the system `com.apple.iokit.IOAudioFamily` and IOGraphicsFamily, meant for `/Library/Extensions`. That is the one built here.

## The patch

`legion.patch` changes `tranc/VoodooHDADevice.cpp` in three places:

1. **Layout priority.** VoodooHDA reads the layout from the `voodoo-layout-id` boot-arg, then from the `layout-id` property of the PCI device (which OpenCore DeviceProperties or AppleALC's own injection set for AppleHDA), and only then from the pin-config tables. On this laptop the PCI property says 7, an AppleHDA layout, not a VoodooHDA one, and the wrong pin configuration follows. The patch reads a `LayoutId` number from the kext personality first (when no boot-arg is set); the build script sets it to 18, the AppleALC pin configuration for `10EC0257` that VoodooHDA ships in `AppleALCPinConfigs.cpp`.
2. **Mixer bound check.** The user client's SetMixer action takes the slider number straight from the caller and `audioCtlOssMixerSet` writes `pcmDevice->left[dev]` and `right[dev]` with it. The arrays have `SOUND_MIXER_NRDEVICES` (25) entries and `dev` can be 0 to 255, so any process that can open the user client can write about 230 bytes past the array in kernel memory. The patch rejects `dev >= SOUND_MIXER_NRDEVICES` in both places the value passes through.
3. **Null check.** `setMath` dereferenced `engine->mChannel` without checking it; the patch returns early when it is null.

## The Info.plist edits

Upstream's `VoodooHDA` personality matches any PCI multimedia device (`IOPCIClassMatch 0x04000000&0xfffc0000`) with a probe score of 100000, which beats Apple's AppleGFXHDA on the NVIDIA and iGPU HDMI audio functions too. The build script replaces that with `IOPCIMatch 0x7f508086` (the Arrow Lake-HX HDA controller only), deletes the separate HDMI personality, and sets `LayoutId 18`.

## Build and provenance

The script clones upstream at commit `beb415a15eca37c5aedb30c1cac95851cce53c96` (2026-10-10), refuses any other commit or local change, copies `tranc/` aside, applies the patch to the copy, and compiles the Sources build phase of `VoodooHDA_LE.xcodeproj` with the same defines and flags (`-O3 -ffast-math -msse4`, `MULTICHANNEL`, `DP_AUDIO`, `LINK_IOGRAPHICSFAMILY`, per-file hidden visibility for the blitter files). It links against the Command Line Tools SDK's libkmod and checks that the result is a kext bundle with `kmod_info`, lists the undefined symbols, and asks `kmutil libraries` (read-only) which installed kernel extensions resolve them, so a KPI missing on your macOS shows before you install.

## Installing on Tahoe

`/Library/Extensions` kexts on a hackintosh need SIP to allow unsigned and unapproved kexts; the test laptop runs with `csr-active-config 0x0A43` (set by OpenCore). Copy the kext, make it root-owned, run `kmutil install --volume-root / --update-all` to rebuild the auxiliary kernel collection, reboot. The first boot after a new AuxKC takes longer. Rollback is the reverse.
