#!/bin/bash
# <wtl> project: voodoohda-legion | file: build.sh | author: watchthelight </wtl>
# Builds the VoodooHDA LE variant (links the system IOAudioFamily, for /Library/Extensions) for macOS Tahoe with
# the Command Line Tools only (no Xcode), from CloverHackyColor/VoodooHDA at an audited commit plus legion.patch.
#   ./build.sh [source-repo] [build-dir]
#   source-repo defaults to ./VoodooHDA (cloned at the audited commit on first run)
#   build-dir   defaults to ./out (output: out/VoodooHDA.kext)
# Source list, defines and Info.plist follow tranc/VoodooHDA_LE.xcodeproj (Release). Our changes:
#   legion.patch: bound checks in the user-client mixer path, a null check in setMath, and a nonzero
#   personality LayoutId taking priority over the PCI layout-id; plus the Info.plist edits below.
# Nothing is loaded or installed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC_REPO=${1:-$HERE/VoodooHDA}
BUILD=${2:-$HERE/out}
AUDITED=beb415a15eca37c5aedb30c1cac95851cce53c96
NAME=VoodooHDA
KEXT_ID=org.voodoo.driver.VoodooHDA
KEXT_VERSION=3.7.0
LAYOUT=18              # AppleALC pin config set for 10EC0257 layout 18 (AppleALCPinConfigs.cpp)
PCI_MATCH=0x7f508086   # Arrow Lake-HX HDA controller only (not the RTX 5070 or iGPU HDMI functions)

if [ ! -d "$SRC_REPO/.git" ]; then
  echo "cloning CloverHackyColor/VoodooHDA into $SRC_REPO"
  git clone -q https://github.com/CloverHackyColor/VoodooHDA "$SRC_REPO"
  git -C "$SRC_REPO" checkout -q "$AUDITED"
fi
head=$(git -C "$SRC_REPO" rev-parse HEAD)
[ "$head" = "$AUDITED" ] || { echo "FAIL: $SRC_REPO is at $head, audited commit is $AUDITED"; exit 1; }
git -C "$SRC_REPO" diff --quiet HEAD -- tranc || { echo "FAIL: $SRC_REPO/tranc has local changes"; exit 1; }

# fresh copy of the sources, then our patch (the clone itself is never modified)
rm -rf "$BUILD/tranc" "$BUILD/$NAME.kext" "$BUILD/obj"
mkdir -p "$BUILD/obj"
rsync -a --exclude '*.xcodeproj' "$SRC_REPO/tranc/" "$BUILD/tranc/"
patch -s -p0 -d "$BUILD" < "$HERE/legion.patch"
cd "$BUILD/tranc"

# Sources build phase of VoodooHDA_LE.xcodeproj (the embedded IOAudioFamily/*.cpp are not part of LE)
SRCS="VoodooHDAFramebufferNotifier.cpp VoodooHDADevice.cpp VoodooHDAEngine.cpp NotificationExtra.cpp
 Tables.c Parser.cpp VoodooHDAUserClient.cpp TigerAdditionals.cpp AppleAudioClip.cpp PCMBlitterLib.cpp
 PCMBlitterLibX86.cpp AppleALCPinConfigs.cpp"
HIDDEN="AppleAudioClip.cpp PCMBlitterLib.cpp PCMBlitterLibX86.cpp"   # per-file -fvisibility=hidden in the project

SDK=$(xcrun --sdk macosx --show-sdk-path)
K=$SDK/System/Library/Frameworks/Kernel.framework/Headers
RES=$(clang -print-resource-dir)
OUT=$BUILD/$NAME.kext/Contents
mkdir -p "$OUT/MacOS"

# project settings: x86_64, 10.13 minimum, -O3, fast math, -msse4, MULTICHANNEL, DP_AUDIO, LINK_IOGRAPHICSFAMILY
FLAGS="-arch x86_64 -mmacosx-version-min=10.13 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector
 -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -DMULTICHANNEL -DDP_AUDIO -DLINK_IOGRAPHICSFAMILY
 -msse4 -ffast-math -isystem $RES/include -I$K -I. -O3 -g0 -Wno-deprecated-declarations -w"
CXXFLAGS="$FLAGS -fapple-kext -std=gnu++17 -nostdinc++ -fno-exceptions -fno-rtti -fno-use-cxa-atexit
 -fno-register-global-dtors-with-atexit"
OBJS=""
for s in $SRCS; do
  o=$BUILD/obj/$(basename "${s%.*}").o
  extra=""
  case " $HIDDEN " in *" $s "*) extra="-fvisibility=hidden" ;; esac
  case "$s" in
    *.cpp) clang++ $CXXFLAGS $extra -c "$s" -o "$o" ;;
    *.c)   clang $FLAGS -std=gnu11 $extra -c "$s" -o "$o" ;;
  esac
  OBJS="$OBJS $o"
done
clang $FLAGS -std=gnu11 -DKEXT_ID=$KEXT_ID -DKEXT_VERSION="\"$KEXT_VERSION\"" \
  -c "$HERE/src/kmod_info.c" -o "$BUILD/obj/kmod_info.o"
clang++ -arch x86_64 -mmacosx-version-min=10.13 -nostdlib -Xlinker -kext -Xlinker -export_dynamic \
  $OBJS "$BUILD/obj/kmod_info.o" -L"$SDK/usr/lib" -lkmodc++ -lkmod "$RES/lib/darwin/libclang_rt.cc_kext.a" \
  -o "$OUT/MacOS/$NAME" 2>&1 | grep -v 'was built for newer macOS version' >&2 || true
[ -f "$OUT/MacOS/$NAME" ] || { echo "FAIL: link"; exit 1; }

# Info.plist: Info-LE.plist with the Xcode variables filled in, then our match and layout
PB=/usr/libexec/PlistBuddy
PL=$OUT/Info.plist
cp Info-LE.plist "$PL"
$PB -c "Set :CFBundleExecutable $NAME" -c "Set :CFBundleIdentifier $KEXT_ID" -c "Set :CFBundleName $NAME" \
    -c "Set :CFBundleShortVersionString $KEXT_VERSION" -c "Set :CFBundleVersion $KEXT_VERSION" "$PL"
$PB -c "Delete :IOKitPersonalities:VoodooHDA-HDMI" \
    -c "Delete :IOKitPersonalities:VoodooHDA:IONameMatch" \
    -c "Add :IOKitPersonalities:VoodooHDA:IOPCIMatch string $PCI_MATCH" \
    -c "Set :IOKitPersonalities:VoodooHDA:LayoutId $LAYOUT" "$PL"
plutil -lint "$PL" >/dev/null
if grep -q '\$[({]' "$PL"; then echo "FAIL: unexpanded variable in Info.plist"; exit 1; fi
if [ -d English.lproj ]; then mkdir -p "$OUT/Resources"; cp -R English.lproj "$OUT/Resources/"; fi

# offline checks: MH_KEXT_BUNDLE, kmod_info, undefined symbols, no C++ runtime the kernel lacks
# (operator new/delete, __Znwm/__ZdlPv, are fine: Tahoe's com.apple.kpi.libkern exports them)
BIN=$OUT/MacOS/$NAME
otool -hv "$BIN" | grep -q KEXTBUNDLE && echo "filetype: MH_KEXT_BUNDLE" || { echo "FAIL: not MH_KEXT_BUNDLE"; exit 1; }
nm "$BIN" | grep -q ' _kmod_info$' && echo "kmod_info: present" || { echo "FAIL: no kmod_info"; exit 1; }
nm -u "$BIN" | sort > "$BUILD/undefined.txt"
echo "undefined symbols: $(wc -l < "$BUILD/undefined.txt" | tr -d ' ') ($BUILD/undefined.txt)"
if grep -E '^_{2,3}(cxa_|Unwind|gxx_)|^__ZTV.*__cxxabiv' "$BUILD/undefined.txt"; then
  echo "FAIL: C++ runtime symbols the kernel does not export"; exit 1
fi
# which libraries resolve those symbols on the running system (reads the installed collections, changes nothing)
if kmutil libraries -p "$BUILD/$NAME.kext" --undef-symbols > "$BUILD/libraries.txt" 2> "$BUILD/libraries.err"; then
  grep ' in ' "$BUILD/libraries.txt" | sed 's/.*: //' | sort | uniq -c
  missing=$(comm -23 <(sed 's/^ *//' "$BUILD/undefined.txt" | sort -u) \
                     <(grep ' in ' "$BUILD/libraries.txt" | awk '{print $1}' | sort -u))
  [ -z "$missing" ] && echo "all undefined symbols resolve" || { echo "FAIL: unresolved:"; echo "$missing"; exit 1; }
else
  echo "kmutil libraries: failed ($BUILD/libraries.err)"
fi
echo "built $KEXT_ID $KEXT_VERSION: $BIN ($(stat -f %z "$BIN") bytes)"
echo "sha256: $(shasum -a 256 "$BIN" | cut -c1-64)"
