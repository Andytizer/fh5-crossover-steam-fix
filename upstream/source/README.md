# FH5 D3DMetal d3d12 proxy

A `d3d12.dll` proxy that sits in front of Apple's D3DMetal (GPTK) and lets **Forza Horizon 5 (Steam)** run on
Apple Silicon Macs under Wine. It forwards everything to the real D3DMetal `d3d12.dll` and patches a handful of
behaviours that D3DMetal gets wrong or lacks. It also includes two small ntdll patch tools for the Wine runner and install instructions.

It is built on **tsshim** from [Highball](https://github.com/gauthierpiarrette/highball) by Gauthier Piarrette
(GPL-3.0), so this repo is GPL-3.0 as well.

No game files are included or modified. The only additions to the game folder are the proxy DLL itself.
You need your own legitimately owned Steam copy.

## Tested setup

| | |
|---|---|
| Machine | M5 MacBook Air, 16 GB, macOS 27 |
| Game | Steam Forza Horizon 5, build 21856128 (Ver. 688.109) |
| Runner | Bridgeplay with the Highball CrossOver 26.3 r28 runner |
| Graphics | Apple GPTK 4.0 beta 3 D3DMetal |
| Result | About 60 fps at 1710x1112 with DLSS (mapped to MetalFX) Quality; 30+ minute free-roam sessions; prologue and its 4th ride pass; online works (Horizon Life, Horizon Open with 8 players) |

Other hardware, game builds and runners are untested. The proxy matches D3DMetal behaviour seen on 4.0b3, and the
ntdll patch tools only accept the exact Highball r28 ntdll it was written for.

## What it does

- **Timestamp queries (tsshim base).** D3DMetal 3.0/4.0 has no D3D12 timestamp queries: the query heap exists
  but `EndQuery`/`ResolveQueryData` do nothing, so games that time frames read garbage. The proxy answers
  timestamp heaps itself using the CPU clock. It also handles `CheckFeatureSupport(SHADER_MODEL)` for models
  D3DMetal does not know (asks again with lower values, as Windows does), drops a multisampled-depth
  `ResolveSubresource` that ends in a Metal assertion, writes `D3D12_APPEND_ALIGNED_ELEMENT` input-layout offsets
  explicitly, and switches off a render-target-0 blend in pipelines that have no render target.
- **Descriptor stride (fixes `Fatal Error 0x800705AA` in free roam and at the 4th intro ride).** D3DMetal
  reports a CBV/SRV/UAV descriptor increment of 24 bytes; NVIDIA drivers and Mullion report 32. FH5 sizes its
  main descriptor pool as 1,000,000 x that increment, carves out a fixed ~18.4 MB static part, and uses the rest
  for dynamic descriptors. At 24 bytes that leaves room for about 234k dynamic descriptors; at 32 bytes about
  426k. Free roam needs roughly 240-246k, so on D3DMetal the pool runs dry and the game calls its fatal-error
  routine with a hard-coded `ERROR_NO_SYSTEM_RESOURCES` (0x800705AA). The proxy reports 32 and gives each
  CBV/SRV/UAV heap fake CPU/GPU start handles, then translates every handle the game passes back to the real
  24-byte layout (`stride.h`, `stride_math.h`). It also answers `IDXGIAdapter::CheckInterfaceSupport` (UMD driver
  version) if D3DMetal fails it.
- **Dual-source blend rewrite (fixes missing / black objects).** D3DMetal forces dual-source blending when render
  target 0 blends with an SRC1 factor, and Metal only accepts that if the pixel shader writes exactly
  SV_Target0 + SV_Target1. FH5 has many such pipelines whose shaders write a different set of targets, so
  D3DMetal rejects them ("Failed to compile fragment function") and the draws silently do nothing (2,784
  pipelines were affected on the tested setup). The proxy parses the pixel shader's outputs and, when it is not
  dual-source, rewrites the SRC1 factors to the single-source ones (SRC1_COLOR -> SRC_COLOR and so on) in its
  own copy of the pipeline description.
- **Unwind guard (`unwindguard.h`).** FH5 calls `RtlVirtualUnwind` directly on captured thread contexts.
  In Wine's `RtlVirtualUnwind2` / `RtlVirtualUnwind` that can fault on garbage pointers. A first-chance exception handler
  catches access violations inside those two functions when called from game code, unwinds one frame out of the
  faulting function and makes it return failure instead of killing the process.
- **SV_ShadingRate (`dxil_shadingrate.c`).** Pixel shaders that read SV_ShadingRate are given
  SV_ViewportArrayIndex (0) instead, since Metal refuses the former. Present from the FH6 work; harmless here.
- **memfix (`memfix.h`).** Replaces `K32GetProcessMemoryInfo` so memory counters cannot exceed real RAM (Wine
  reports about 140 GB). It is on by default and was on in the tested FH5 setup
  (`HB_FH6_MEMFIX=0` turns it off). A second, opt-in fiber fix (`HB_FH6_FIBERFIX=1`) is
  for FH6 and crashes at startup on Bridgeplay; leave it off.

- **Online (Horizon Life / Horizon Open).** FH5 opens its Xbox Live UDP socket as a dual-stack IPv6 socket on port
  3074, then calls `WSAIoctl(SIO_UDP_NETRESET)` (Wine: unsupported) and `setsockopt(IPPROTO_IP, IP_TTL, 255)`
  (macOS refuses IPv4 options on an IPv6 socket). Both fail, so the game drops the socket and stays in offline
  mode. `bin/ws2_32.dll` is a `ws2_32` wrapper that makes `SIO_UDP_NETRESET` succeed and applies the IPv6
  equivalent of failing IPv4 socket options. Details in `tools/ws2_32-netfix/README.md`.

## Prebuilt DLL

`bin/d3d12.dll` is built from this source with `./build.sh` (SHA-256 in `bin/d3d12.dll.sha256`). Use it directly, or
build your own as below.

## Build

Needs Docker only (nothing is installed on the host):

    ./build.sh

This runs `x86_64-w64-mingw32-clang -shared -O2 -Wall -static-libgcc` from the `mstorsjo/llvm-mingw` image on
`src/` and writes `build/d3d12.dll`, then prints its SHA-256 and export table. The output matches the
author's installed build except for the PE timestamp and the DLL's internal export name
(`d3d12.dll` here). Logging is compiled in but off unless `HB_DEBUG=1`.

## Install

There are two ways: let an AI coding agent do it from a prompt (Option A), or follow the steps yourself
(Option B). Option A is only a guided version of Option B, so Option B is the specification for both.

What you need first: an Apple Silicon Mac, [Bridgeplay](https://github.com/raymondchins/Bridgeplay) installed (tested
with app version 0.7.62), Steam with your own copy of Forza Horizon 5 (app 1551360) installed, and Rosetta 2.
Everything below is written for the layout of that tested setup. Paths use `$HOME`; nothing here needs `sudo`.

Five things have to be put in place, and the steps below cover each:

1. A **runner**: the Highball CrossOver 26.3 r28 Wine, set up as a Bridgeplay runner and Steam compatibility tool.
2. Two small patches to the runner's `ntdll.dll`: the Steam detour port (`tools/ntdll-steam-detour/`) and the
   unwind fix (`tools/ntdll-unwindfix/`).
3. The real D3DMetal `d3d12.dll` under the name `apd12.dll`, plus this repo's `d3d12.dll` in the game folder.
4. A Bridgeplay gamefix file and the Steam launch options.
5. For online play, the `ws2_32` network fix (`tools/ws2_32-netfix/`), Step 8b.

### Option A - Install with an AI coding agent

Use an agent that can run shell commands on your Mac (Claude Code, Codex, and similar). Clone this repo, open the
agent in the clone, and paste the prompt below. The agent will first look at your machine and report, then give
you a numbered plan and wait for your approval before it changes anything. Read the plan; you are still the one
who approves each change.

```text
You are installing the Forza Horizon 5 D3DMetal fix from this repository onto my Mac. The spec is "Option B -
Manual install" in README.md: read it fully first and follow it exactly (same paths, same commands, same
order). Do not invent other methods.

Rules:
1. Inspect first, change nothing. Report: is Steam installed, is Bridgeplay installed (app version), is Forza
   Horizon 5 (Steam app 1551360) installed and at what path, which Bridgeplay runners exist under
   "$HOME/Library/Application Support/bridgeplay/runners", which compatibility tools exist under
   "$HOME/Library/Application Support/Steam/compatibilitytools.d", what is in
   "$HOME/Library/Application Support/bridgeplay/tools", whether the FH5 prefix
   ("$HOME/Library/Application Support/Steam/steamapps/compatdata/1551360") exists, and whether Steam is running.
2. Then write a numbered plan that maps to the steps of Option B, with the exact files each step creates,
   changes or replaces. STOP and wait for my explicit approval. Do not start before I say so.
3. Before replacing or editing any existing file, copy it next to itself with the suffix .orig (if a .orig
   exists, stop and ask). Never overwrite a .orig. After each step print what changed. At the end print an
   "undo list": every file or folder you created, and every .orig you made with the command to restore it.
4. Do not install host packages (no brew, pip, npm, etc.). macOS tools (curl, tar, shasum, perl, cp, ln, sed) are
   fine. If something needs Python (tools/ntdll-steam-detour/port_detour.py, tools/pe_tools.py) run it in a
   Docker python image with only the needed folders mounted, and if Docker is not available, ask me. Use
   bin/d3d12.dll from this repo instead of building it, unless I ask you to build.
5. Verify every step as Option B describes: sha256 of downloads and of the patched ntdll, file existence,
   symlink targets, and the export table of the DLLs. If a check fails, stop and tell me; do not continue.
6. Never touch game files except adding one file, d3d12.dll, in the Forza Horizon 5 folder. Do not modify,
   move or delete anything else in the game folder, and never touch saves or compatdata/1551360 other than
   reading it.
7. Do not edit Steam's own config files (config.vdf, localconfig.vdf) while Steam is running, and prefer not to
   edit them at all. At the end, tell me exactly what to set in Steam myself: the compatibility tool and the
   launch options from Option B step 9.
8. Do not publish, upload or push anything, and do not send any file from my machine anywhere.
9. The online step (Step 8b, the ws2_32 network fix) is part of Option B and must be followed too, including
   the gamefix line and copying ws2_o.dll to both places.
10. Do not copy the patched ntdll.dll or any Bridgeplay file into this repo.
```

### Option B - Manual install

Open Terminal and set these once; the steps use them. Nothing is installed on your Mac except files in the folders
named here.

```sh
BP="$HOME/Library/Application Support/bridgeplay"
STEAM="$HOME/Library/Application Support/Steam"
RUN="$BP/runners/crossover-hb26r28/CrossOver"
REPO=/path/to/your/clone/of/this/repo
WORK="$HOME/fh5-r28-work"
mkdir -p "$WORK"
```

Quit Steam before steps 7 and 9 (Bridgeplay reads its `tools` list when Steam starts).

**Step 1 - Check the prerequisites.**

```sh
ls "$BP/tools" "$BP/gptk/wine/x86_64-windows/d3d12.dll" "$BP/runners/crossover-winecx-11.17/CrossOver/bin/wine"
ls "$STEAM/steamapps/common/ForzaHorizon5/ForzaHorizon5.exe"
```

All must exist. The stock Bridgeplay runner `crossover-winecx-11.17`, its `bridgeplay-proton-winecx-11.17` Steam
tool and Bridgeplay's own `gptk` folder (D3DMetal 4.0 beta 3) are used as sources below. This repo only reads them.

**Step 2 - Download the Highball r28 engine and the runtime.** Highball publishes the engine as release assets.
The exact URLs and hashes come from Highball's manifest `spike/engines/x64-crossover26.3-r28.json`:

```sh
cd "$WORK"
curl -L -O "https://github.com/gauthierpiarrette/highball-engine/releases/download/engine-wine-11.0-20261014T003801Z-0024-app-packages-0023-spatial-mixer/engine-wine-11.0-20261014T003801Z-0024-app-packages-0023-spatial-mixer.tar.gz"
curl -L -O "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz"
shasum -a 256 engine-wine-*.tar.gz Template-1.0.11.tar.xz
```

Verify: the two hashes must be

    1d1a130c0108a4bbb88cd289c3c313292868c3b84010eb315801eba43026e3e8  engine-wine-11.0-...tar.gz  (334884359 bytes)
    9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a  Template-1.0.11.tar.xz      (84533420 bytes)

If GitHub release downloads are blocked on your network, download them another way; only the hashes matter.
Then unpack:

```sh
mkdir -p wine runtime
tar xzf engine-wine-*.tar.gz -C wine
tar xJf Template-1.0.11.tar.xz -C runtime
ls wine/engine            # bin  lib  share
```

**Step 3 - Assemble the runner folder.** Bridgeplay looks for `runners/crossover-<build>/CrossOver`, with build
`hb26r28`. The runner is the Highball engine plus the runtime's dylibs, plus a few Bridgeplay-specific files taken
from the stock `winecx-11.17` runner:

```sh
mkdir -p "$BP/runners/crossover-hb26r28"
test ! -e "$RUN" || { echo "runner already exists, stop"; false; }
cp -R "$WORK/wine/engine" "$RUN"
# runtime dylibs (links are kept as links)
cp -a "$WORK"/runtime/Template-1.0.11.app/Contents/Frameworks/*.dylib "$RUN/lib/"
# SDL2 comes from the stock Bridgeplay runner, not from the template
CX="$BP/runners/crossover-winecx-11.17/CrossOver"
cp -a "$CX/lib/libSDL2-2.0.0.dylib" "$RUN/lib/"
# Bridgeplay's own pieces, same as in the stock runner
cp -R "$CX/lib/notproton-backends" "$RUN/lib/"
cp "$CX/.notproton-msync" "$RUN/"
cp "$CX/lib/wine/x86_64-windows/lsteamclient.dll" "$RUN/lib/wine/x86_64-windows/"
cp "$CX/lib/wine/i386-windows/lsteamclient.dll" "$RUN/lib/wine/i386-windows/"
cp "$CX/lib/wine/x86_64-unix/lsteamclient.so" "$RUN/lib/wine/x86_64-unix/"
# every runtime dylib must also be visible from lib/wine/x86_64-unix (for example gnutls)
for f in "$RUN"/lib/*.dylib; do n=${f##*/}; ln -sf "../../$n" "$RUN/lib/wine/x86_64-unix/$n"; done
```

Verify:

```sh
"$RUN/bin/wine" --version            # wine-11.0 ...
ls -d "$RUN"/lib/wine/x86_64-unix/libgnutls.30.dylib
```

On the tested machine the finished runner has 94 `.dylib` entries in `lib/` and the same 94 as links in
`lib/wine/x86_64-unix/`. If `bin/wine --version` fails with a missing library, a dylib link is missing.

**Step 4 - Link Bridgeplay's D3DMetal into the runner.** Absolute symlinks into Bridgeplay's `gptk` folder, as in
the tested runner:

```sh
G="$BP/gptk"
mkdir -p "$RUN/lib/external"
ln -sf "$G/external/libd3dshared.dylib" "$RUN/lib/external/libd3dshared.dylib"
W="$RUN/lib/wine/x86_64-windows"; U="$RUN/lib/wine/x86_64-unix"
for n in d3d10 d3d11 d3d12 d3d12core dxgi; do
  ln -sf "$G/wine/x86_64-windows/$n.dll" "$W/$n.dll"
  ln -sf "$G/wine/x86_64-unix/$n.so"     "$U/$n.so"
done
ln -sf "$G/wine/x86_64-windows/nvapi64.dll"          "$W/nvapi.dll"
ln -sf "$G/wine/x86_64-windows/nvapi64.dll"          "$W/nvapi64.dll"
ln -sf "$G/wine/x86_64-windows/nvngx-on-metalfx.dll" "$W/nvngx.dll"
ln -sf "$G/wine/x86_64-unix/nvapi64.so"              "$U/nvapi.so"
ln -sf "$G/wine/x86_64-unix/nvapi64.so"              "$U/nvapi64.so"
ln -sf "$G/wine/x86_64-unix/nvngx-on-metalfx.so"     "$U/nvngx.so"
```

Verify: `ls -l "$W/d3d12.dll" "$U/d3d12.so"` shows links that resolve (`test -e "$W/d3d12.dll" && echo ok`).

**Step 5 - Create `apd12.dll` and `apd12.so`.** This is Bridgeplay's D3DMetal `d3d12.dll` under another name, so
that the proxy in the game folder (which is the one named `d3d12.dll`) can load the real one. The DLL's internal
export name must be changed as well, or Wine hands back the first `d3d12.dll` it loaded. The helper is
`tools/pe_tools.py` and needs Python 3 (use a Docker `python:3-slim` container if you do not have one):

```sh
cp "$G/wine/x86_64-windows/d3d12.dll" "$W/apd12.dll"
python3 "$REPO/tools/pe_tools.py" rename-export "$W/apd12.dll" apd12.dll
ln -sf "$G/wine/x86_64-unix/d3d12.so" "$U/apd12.so"
shasum -a 256 "$W/apd12.dll"
```

Verify: the hash is `af5db5201dfc2bb98febecafb69239a99c5b4a6b0bd3b1b0e6b24f2b75cbcbb5` when your Bridgeplay's
D3DMetal is the 4.0b3 one used here (the source `d3d12.dll` of that build has the prefix `3174fac0`). A different
hash means a different D3DMetal build; that is untested.

**Step 6 - Patch the runner's `ntdll.dll`.** Two patches, in this order. Keep the original.

```sh
cd "$W"
cp ntdll.dll ntdll.dll.orig
shasum -a 256 ntdll.dll.orig
```

Verify: the stock Highball r28 `ntdll.dll` is 1153043 bytes with SHA-256
`e606762e531e8d749cb4075a3fea2ba063f4833dad9903074ec1762f91efc1a3`.

a. Steam detour port. It reads your own Bridgeplay `ntdll.dll` (the WineCX 11.17 runner's, which carries
Bridgeplay's `steamclient64` detour) and the Highball `ntdll.dll`, and writes a Highball `ntdll.dll` with the same
detour. See `tools/ntdll-steam-detour/README.md`. Python 3 stdlib only:

```sh
python3 "$REPO/tools/ntdll-steam-detour/port_detour.py" \
    "$CX/lib/wine/x86_64-windows/ntdll.dll" "$W/ntdll.dll.orig" "$WORK/ntdll.detour.dll"
shasum -a 256 "$CX/lib/wine/x86_64-windows/ntdll.dll" "$WORK/ntdll.detour.dll"
```

Verify: the script prints `ok: cave at RVA 0x7a0a0, hook at RVA 0x484f3, 723 bytes changed`. The Bridgeplay
input has SHA-256 `4573d521671a48212670e7543aa9ebf0921e383dada69477f677f435df2bef5a` and the output
`ff8bcf2574bc0b571509401729bb7545446f753c612eb47d015bfbb669feff10`. (If your Bridgeplay input differs, the script
may refuse or the result may differ; that is untested.)

b. Unwind fix (`tools/ntdll-unwindfix/`, Perl, already on macOS):

```sh
perl "$REPO/tools/ntdll-unwindfix/patch_unwind.pl" "$WORK/ntdll.detour.dll" "$WORK/ntdll.final.dll"
shasum -a 256 "$WORK/ntdll.final.dll"
```

Verify: it prints `ok: hook RVA 0x3b1a0 -> cave 0x7a400 ...` and the result has SHA-256
`1cd92d93a4569ef9486c506479d8c4162022eb64c5dbb84449c72bf55f2ec522` (starts with `1cd92d93`).

c. Install it in two places: the runner, and the copy Bridgeplay keeps per build for its Steam bridge:

```sh
cp "$WORK/ntdll.final.dll" "$W/ntdll.dll"
mkdir -p "$BP/bridge/wine/hb26r28/x86_64-windows"
cp "$WORK/ntdll.final.dll" "$BP/bridge/wine/hb26r28/x86_64-windows/ntdll.dll"
shasum -a 256 "$W/ntdll.dll" "$BP/bridge/wine/hb26r28/x86_64-windows/ntdll.dll"
```

Verify: both lines start with `1cd92d93`.

**Step 7 - Register the tool with Bridgeplay and Steam (Steam quit).** Bridgeplay deletes Steam compatibility tools
that are not listed in `bridgeplay/tools` (tab-separated: tool name, build, flavor, display name). Add the line first:

```sh
cp "$BP/tools" "$BP/tools.orig"
printf 'bridgeplay-proton-hb26r28\thb26r28\trosetta\tHighball CX26.3 r28 (msync, D3DMetal)\n' >> "$BP/tools"
cat "$BP/tools"
```

The Steam tool folder is a copy of the stock Bridgeplay tool with the build, the name and the display name changed:

```sh
T="$STEAM/compatibilitytools.d"
cp -R "$T/bridgeplay-proton-winecx-11.17" "$T/bridgeplay-proton-hb26r28"
cd "$T/bridgeplay-proton-hb26r28"
echo hb26r28 > build
sed -i '' -e 's/bridgeplay-proton-winecx-11.17/bridgeplay-proton-hb26r28/' \
          -e 's/WineCX 11.17 (msync, D3DMetal)/Highball CX26.3 r28 (msync, D3DMetal)/' compatibilitytool.vdf
cat build flavor compatibilitytool.vdf
```

Verify: `build` says `hb26r28`, `flavor` says `rosetta`, and `compatibilitytool.vdf` has the new name and the display
name `Highball CX26.3 r28 (msync, D3DMetal)`. The `run` and `toolmanifest.vdf` files stay as copied. Bridgeplay
rewrites these files itself at times, so on the tested machine they carry later timestamps than the copy; whether
it would create the folder by itself from the `tools` line was not tested.

**Step 8 - Gamefix and proxy.**

```sh
cp "$BP/gamefixes/1551360.conf" "$BP/gamefixes/1551360.conf.orig" 2>/dev/null   # only if one exists
printf 'DLLOVERRIDES=d3d12=n;ws2_32=n,b\n' > "$BP/gamefixes/1551360.conf"
GAME="$STEAM/steamapps/common/ForzaHorizon5"
test ! -e "$GAME/d3d12.dll" || cp "$GAME/d3d12.dll" "$GAME/d3d12.dll.orig"   # a stock install has none
cp "$REPO/bin/d3d12.dll" "$GAME/d3d12.dll"
shasum -a 256 "$GAME/d3d12.dll"
```

Verify: the hash equals the one in `bin/d3d12.dll.sha256`. `DLLOVERRIDES=d3d12=n` makes Wine load the `d3d12.dll` in the game
folder (the proxy) instead of its own. This is the only file added to the game folder. If you prefer to build the DLL
yourself, see "Build" above.

**Step 8b - Online: the ws2_32 network fix.** Without it the game stays in offline mode
(see `tools/ws2_32-netfix/README.md`). The wrapper `bin/ws2_32.dll` forwards to the original Wine `ws2_32`, which
you provide as `ws2_o.dll`, made from your runner's own `ws2_32.dll`. The internal name must not be longer than
`ws2_32.dll`:

```sh
cp "$W/ws2_32.dll" "$W/ws2_o.dll"
python3 "$REPO/tools/pe_tools.py" rename-export "$W/ws2_o.dll" ws2_o.dll
ln -s ws2_32.so "$U/ws2_o.so"
P="$STEAM/steamapps/compatdata/1551360/pfx/drive_c/windows/system32"
cp "$W/ws2_o.dll" "$P/ws2_o.dll"          # Wine looks in system32; the runner copy alone gives
                                          # "module not found for forward 'ws2_o.…'", so both are needed
cp "$P/ws2_32.dll" "$P/ws2_32.dll.orig"   # back up the stock one (if a .orig exists, stop)
cp "$REPO/bin/ws2_32.dll" "$P/ws2_32.dll"
shasum -a 256 "$P/ws2_32.dll"
```

This needs the prefix to exist (it is created at the first launch, Step 10); if it does not yet, do this step after
Step 10. The gamefix line in Step 8 already contains `ws2_32=n,b`. Verify: the hash equals `bin/ws2_32.dll.sha256`.
In the game, the Online tab shows Friends/Players and Horizon Open matchmakes. Optionally add
`NOTPROTON_ENV_HB_NETLOG=1` to the launch options: `/tmp/hb-net.log` then shows a line like
`setsockopt ... level=0 opt=4 ... (wrapper forced success)`.

**Step 9 - Steam settings.** Start Steam. In the Forza Horizon 5 properties:

- Compatibility: tick "Force the use of a specific Steam Play compatibility tool" and choose
  **Highball CX26.3 r28 (msync, D3DMetal)** (the tool's display name; Steam may shorten it in the list).
- General > Launch options (one line):

      CX_GRAPHICS_BACKEND=d3dmetal BRIDGEPLAY_DISABLE_HIDRAW=1 NOTPROTON_ENV_HB_D3D12_REAL='C:\windows\system32\apd12.dll' D3DM_VENDOR_ID=4318 D3DM_DEVICE_ID=10118 D3DM_DEVICE_DESCRIPTION='NVIDIA GeForce RTX 4070' %command%

  - `D3DM_VENDOR_ID=4318 D3DM_DEVICE_ID=10118` (0x10DE / 0x2786) present an NVIDIA RTX 4070 identity to the game;
    the description string goes with it. This avoids the game's GPU checks / endless loading.
  - `BRIDGEPLAY_DISABLE_HIDRAW=1` makes a DualSense go through SDL as an Xbox-style controller.
  - DLSS maps to MetalFX automatically; keep Frame Generation off.

Verify: the tool is in the list. If it is not, quit Steam completely and start it again, and check Step 7 (the `tools`
line decides whether Bridgeplay keeps it).

**Step 10 - First launch and prefix check.** The prefix
(`$STEAM/steamapps/compatdata/1551360/pfx`) is created at the first launch, so launch the game once. The first start
can sit on a black screen for several minutes while shaders build. Then check:

```sh
P="$STEAM/steamapps/compatdata/1551360/pfx/drive_c/windows/system32"
ls -l "$P/apd12.dll" && shasum -a 256 "$P/apd12.dll"
```

Verify: `apd12.dll` is there (hash `af5db520...`). If it is missing, close the game and `cp "$W/apd12.dll" "$P/apd12.dll"`. Without it the proxy log (when
logging is on) says it cannot load the real D3DMetal `d3d12.dll`, and the game exits.

**Step 11 - Xbox sign-in (optional, one time).** The "Welcome to XBOX" window uses a WebView2 that renders black
under Wine, so you cannot sign in with it as is. This worked on the tested setup; you may be able to sign in some
other way, and the game folder and prefix are not changed otherwise:

1. With the game closed, add to the prefix `user.reg` (`$STEAM/steamapps/compatdata/1551360/pfx/user.reg`; keep a
   copy first) the section `[Software\\Wine\\AppDefaults\\msedgewebview2.exe]` with `"Version"="win7"`.
2. Add to the launch options, in front of `%command%`:
   `NOTPROTON_ENV_WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--disable-gpu --disable-gpu-compositing --remote-debugging-port=9222'`
3. Launch. The sign-in window turns white. In Chrome open `chrome://inspect`, find the WebView2 page under "Remote
   Target" and click "inspect", then sign in in that window.
4. Afterwards remove both changes (restore the `user.reg` copy, delete the launch option). Win7 mode with the GPU
   enabled crashes, so keep `--disable-gpu`.

Keep Steam Cloud enabled for the game: with it off and no local profile, the game stops at "INVALID PROFILE"
(E:5-60). There is no in-game way to restart from the intro; deleting the save files does not do it.

**Step 12 - After updates.** A Bridgeplay update can change `tools`, the Steam tool folder or the runner (it can
remove the `apd12` files from the runner). After every Bridgeplay update re-check: the `tools` line, the tool
folder, `ntdll.dll` hash `1cd92d93`, and `apd12.dll`/`apd12.so` in the runner. If the runner `ntdll.dll` was
replaced, redo Step 6. Also re-check `ws2_o.dll`/`ws2_o.so` in the runner and `ws2_32.dll`/`ws2_o.dll` in the prefix.

### Uninstall / undo

Quit Steam and the game first. Each line undoes one step:

```sh
# Step 9: in Steam, clear the launch options and the forced compatibility tool for the game.
# Step 8: remove the proxy and the gamefix (restore a .orig if you made one)
rm "$STEAM/steamapps/common/ForzaHorizon5/d3d12.dll"
rm "$BP/gamefixes/1551360.conf"                 # or: mv "$BP/gamefixes/1551360.conf.orig" "$BP/gamefixes/1551360.conf"
# Step 7: restore the tools list and remove the Steam tool folder
mv "$BP/tools.orig" "$BP/tools"
rm -r "$STEAM/compatibilitytools.d/bridgeplay-proton-hb26r28"
# Steps 3-6: remove the runner and the ntdll copy Bridgeplay keeps for it
rm -r "$BP/runners/crossover-hb26r28" "$BP/bridge/wine/hb26r28"
# Step 8b: online fix
P="$STEAM/steamapps/compatdata/1551360/pfx/drive_c/windows/system32"
mv "$P/ws2_32.dll.orig" "$P/ws2_32.dll"
rm "$P/ws2_o.dll" "$RUN/lib/wine/x86_64-windows/ws2_o.dll" "$RUN/lib/wine/x86_64-unix/ws2_o.so"
# Step 10: optional, the copy in the prefix
rm "$STEAM/steamapps/compatdata/1551360/pfx/drive_c/windows/system32/apd12.dll"
```

If you launched the game once with the Highball runner, the prefix `compatdata/1551360` was created or changed by
it; to fall back to the stock tool just pick it again in Steam. Do not delete `compatdata/1551360` unless you have
copied your save and profile files out first: the game keeps its local profile there. `$WORK` can be deleted
(about 1 GB with the downloads).

## Environment variables

Set via Bridgeplay launch options with the `NOTPROTON_ENV_` prefix (as above). All optional.

| Variable | Effect |
|---|---|
| `HB_D3D12_REAL` | Windows path of the real D3DMetal DLL (required for this setup) |
| `HB_DEBUG=1` | Enable all logging and diagnostic counters (logs go under `C:\highball\logs` in the prefix). Off = no files created |
| `HB_D3D12_TSSHIM=0` | Kill switch: forward everything untouched |
| `HB_DESC_STRIDE=0` | Disable the descriptor-stride fix |
| `HB_UMD_VERSION=0` or `a.b.c.d` | Disable / override the UMD driver version answer |
| `HB_TSSHIM_DUALSRC_FIX=0` | Disable the dual-source blend rewrite |
| `HB_TSSHIM_UNUSED_BLEND=0` | Do not switch off RT0 blend in pipelines without render targets |
| `HB_TSSHIM_SHADINGRATE=0` | Do not rewrite SV_ShadingRate |
| `HB_TSSHIM_APPEND_OFFSETS=0` | Pass input layouts through unmodified |
| `HB_TSSHIM_DEPTHRESOLVE=1` | Let multisampled depth `ResolveSubresource` through |
| `HB_UNWINDGUARD=0` | Disable the unwind guard |
| `HB_FH6_MEMFIX=0` | Disable the memory-info clamp (on by default) |
| `HB_FH6_FIBERFIX=1` | Opt-in FH6 fiber fix (not for FH5) |
| `HB_NETFIX=0` | ws2_32 wrapper (not the d3d12 proxy; set the same way with `NOTPROTON_ENV_`): turn the online network fixes off |
| `HB_NETLOG=1` | ws2_32 wrapper: write a UDP activity log to `Z:\tmp\hb-net.log` (`/tmp/hb-net.log`) |
| `HB_TSSHIM_DUMP=1`, `HB_TSSHIM_INSPECT=1` (+ `_PERIOD`, `_WINDOW`, `_MAX`, `_SERIAL`, `_AFTER`, `_WATCH`), `HB_TSSHIM_DEBUG`, `HB_TSSHIM_DUALSRC_LOG`, `HB_TSSHIM_REPLACE`, `HB_TSSHIM_ATOMIC64`, `HB_TSSHIM_DEPTH_EQUAL` | Diagnostics and experiments; see `src/d3d12.c` and `src/inspect.c`. Most need `HB_DEBUG=1` |

## Known issues

- At every start the game shows an **FH302** driver-version warning. Click **Ignore Warning**. Faking the driver
  version through D3DKMT, NVAPI and SetupAPI did not clear it.
- Rare crash while loading: the game raises an exception nobody handles and Wine's dispatcher walks off the top of
  the stack in `RtlVirtualUnwind2`. Relaunching gets past it.
- Rare freeze ("nested exception on signal stack"): macOS fails to deliver a signal to a game thread and
  everything waiting on it hangs. Not fixable from the proxy.
- Online works (Horizon Life, Horizon Open tested with 8 players) with the ws2_32 network fix; Convoy/party voice untested.
- Heavy areas can dip to 40-45 fps on a fanless Air.

## Credits

- **Highball** (tsshim and the CrossOver 26.3 build) by Gauthier Piarrette, GPL-3.0:
  https://github.com/gauthierpiarrette/highball
- **MACxus** FH5 profile (NVIDIA identity and tsshim recipe)
- **Bridgeplay** (the Wine-on-Steam bridge this runs inside): https://github.com/raymondchins/Bridgeplay
- **whyAm-i**'s FH4 Mac patches

## Disclaimer

No game files or Microsoft, Playground or Apple code are included. It works only with a legitimately owned Steam
copy of the game. This project is not affiliated with or endorsed by Playground Games, Microsoft or Apple.
Use at your own risk.

## License

GPL-3.0, see `LICENSE`. `src/d3d12.c` and `src/d3d12.def` start from Highball's tsshim; see `src/ORIGIN.md`.
