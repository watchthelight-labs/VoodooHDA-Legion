# VoodooHDA-Legion

Audio on macOS Tahoe for the Realtek ALC257 behind Intel's Arrow Lake-HX HDA controller (`8086:7F50`, Intel Smart Sound in DSP mode), as found in the Lenovo Legion 5 15IAX10. Tahoe removed AppleHDA, so AppleALC has nothing to patch and the usual `alcid=` route is gone. [VoodooHDA](https://github.com/CloverHackyColor/VoodooHDA) is a self-contained HDA driver that does not need AppleHDA. This repository is a small patch on top of it plus a build script that produces the `LE` variant (links the system IOAudioFamily, installs to `/Library/Extensions`) with the Xcode Command Line Tools, matched to the 7F50 controller only, with the ALC257 pin configuration for layout 18. No VoodooHDA code is copied here; the script clones upstream at an audited commit and applies `legion.patch`.

On macOS Sequoia the same codec works with AppleALC 1.9.8 and `alcid=18`; this is for Tahoe.

## Status

| What | Tested on | Result |
|---|---|---|
| Internal speakers, volume | Legion 5 15IAX10, macOS 26.7.1 (25G241), VoodooHDA 3.7.0 at commit `beb415a` + `legion.patch`, in `/Library/Extensions` | working daily since 2026-10-16; `system_profiler SPAudioDataType` lists Internal Speakers and Internal Microphone from "Voodoo" |
| Internal microphone | same | detected (2 channels, 48 kHz); not yet tested in a call |
| Headphone jack, volume keys, HDMI audio | same | untested; HDMI is not matched on purpose (the PCI match is the 7F50 controller only) |

## What the patch does

`legion.patch`, 3 hunks against `tranc/VoodooHDADevice.cpp`:

1. A nonzero `LayoutId` in the kext's own personality wins over the `layout-id` PCI property. OpenCore and AppleALC set `layout-id` for AppleHDA (7 on this laptop), which is not a VoodooHDA pin-config layout; with this, the personality's `LayoutId 18` (the AppleALC pin configuration for `10EC0257` layout 18, which VoodooHDA carries in `AppleALCPinConfigs.cpp`) is used.
2. A bound check in `audioCtlOssMixerSet` and `changeSliderValue`: the slider number comes from the user client (0 to 255) and indexed `left[]` / `right[]` arrays of 25 entries with no check, a kernel out-of-bounds write reachable from any process that opens the user client.
3. A null check on `engine->mChannel` in `setMath`.

The build script also edits the Info.plist: `IOPCIMatch 0x7f508086` instead of the class match (which would also grab the NVIDIA and iGPU HDMI audio functions with a probe score above Apple's driver), the HDMI personality removed, `LayoutId 18`.

## What it can't do

- VoodooHDA is not AppleHDA: no Apple codec-specific tuning, and the usual VoodooHDA caveats (volume curve, no jack-sense configuration beyond what the parser finds).
- The `LE` variant has to live in `/Library/Extensions`, which on a hackintosh needs SIP configured to allow unsigned and unapproved kexts. The test laptop runs `csr-active-config 0x0A43`. The `BL` variant (OpenCore-injectable, with IOAudioFamily compiled in) is not used here because Tahoe still has Apple's IOAudioFamily in the kernel collection and the duplicate class names would clash.
- One laptop, one codec, one controller.

## Building

```
./build.sh                 # clones CloverHackyColor/VoodooHDA at beb415a into ./VoodooHDA on first run,
                           # applies legion.patch to a copy, builds out/VoodooHDA.kext with the Command Line Tools
```

The script refuses to run if the clone is not at the audited commit. It prints the undefined symbols and asks `kmutil` which installed libraries resolve them (read-only), so a missing KPI shows up before you install anything.

## Installing

With SIP allowing unsigned kexts (see above):

```
sudo cp -R out/VoodooHDA.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/VoodooHDA.kext
sudo kmutil install --volume-root / --update-all
sudo reboot
```

Check with `kmutil showloaded | grep VoodooHDA` and `system_profiler SPAudioDataType`. Rollback: remove the kext from `/Library/Extensions`, run `kmutil install --volume-root / --update-all` again, reboot.

## Credits

- [VoodooHDA](https://github.com/CloverHackyColor/VoodooHDA) (Slice, chris1111 and contributors, BSD-2-Clause), based on FreeBSD `snd_hda`.
- [AppleALC](https://github.com/acidanthera/AppleALC) (acidanthera): the ALC257 layout 18 pin configuration VoodooHDA ships.

## Licence

BSD-2-Clause, the same as VoodooHDA, for the patch and the script (`LICENSE`).
