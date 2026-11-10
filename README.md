# fh5-crossover-steam-fix

FH5 D3DMetal fix for CrossOver.

Scripts that apply xvferxedd's **fh5-d3dmetal-fix** to
**CrossOver** on Apple Silicon Macs, so Forza Horizon 5 (Steam) runs in a CrossOver bottle with D3DMetal,
without Bridgeplay or the Highball runner.

> **Upstream is gone.** The upstream repository and its author's account disappeared in November 2026. Since
> 1.0.1 this repo bundles upstream's two prebuilt DLLs and its complete source at the last commit
> (`ebd20dbe`), unchanged, in `upstream/` (GPL-3.0; see `upstream/README.md`). All credit for the fix stays with
> xvferxedd.

The upstream project does the real work: a `d3d12.dll` proxy in front of D3DMetal (descriptor-stride fix for
`Fatal Error 0x800705AA`, dual-source blend rewrite for black/missing objects, timestamp queries, unwind guard)
and a `ws2_32` wrapper for online play. This repo only adapts the install to CrossOver. Read the upstream
README (`upstream/source/README.md`) for what each fix does.

> Not affiliated with or endorsed by CodeWeavers, Apple, Microsoft or Playground Games. No CrossOver, Apple,
> Microsoft or game files are included. You need your own CrossOver licence and your own Steam copy of FH5.
> Use at your own risk.

## Status

| CrossOver | D3DMetal in app | Result |
|---|---|---|
| Preview 20261015 (27.0.0.41073) | 4.0b3 in `lib/apple_gptk` | Applied to a real install; file-level checks pass; in-game results being collected |
| 26.3 (26.3.0.39832) | **3.0** in `lib64/apple_gptk` | Use `--d3dmetal-from` to swap in 4.0b3 (see below). Static checks and a full setup → uninstall cycle on a copy pass; in game untested |
| Other versions | ? | Run `setup.sh --check` first. It refuses an unsupported ntdll and warns about other differences |

Please open an issue with your `setup.sh --check` output and in-game result for other versions.

## What it does differently from the Bridgeplay setup

| Upstream (Bridgeplay + Highball r28) | CrossOver |
|---|---|
| Real D3DMetal from Bridgeplay's `gptk` folder | CrossOver's own `lib/apple_gptk` (Preview) or `lib64/apple_gptk` (26.3), on Wine's DLL path when the bottle's graphics are D3DMetal. Optionally replaced with 4.0b3 (`--d3dmetal-from`) |
| `apd12.dll`/`.so` in the runner | `lib/apple_gptk/wine/x86_64-{windows,unix}/apd12.*` in the app copy, plus `system32/apd12.dll` in the bottle |
| ntdll Steam detour | Not needed: Windows Steam runs inside the bottle |
| ntdll unwind fix at fixed Highball RVAs | `tools/patch_unwind_cx.pl`: the same cave code, with every address found from the PE (export table, `.text` padding, `.data` slack). Refuses anything that doesn't match. |
| Bridgeplay gamefix `DLLOVERRIDES` | Per-exe registry overrides for `ForzaHorizon5.exe` only (`d3d12=native`, `ws2_32=native,builtin`) |
| `NOTPROTON_ENV_*` launch options | Bottle `cxbottle.conf` `[EnvironmentVariables]` |

The fix needs files inside the CrossOver app bundle. So it is applied to a **copy** of the app, and to a
**copy** of your Steam bottle. Your original app and bottle are never modified.

## Requirements

- Apple Silicon Mac, CrossOver (tested: CrossOver Preview), a Steam bottle (`win64`)
- macOS built-ins only: `sh`, `perl`, `shasum`, `ditto`, `plutil`. No Python, Docker or Xcode needed.
- About 2–3 GB for the app copy, plus the size of your Steam bottle

## Download

The same release zip is published in two places:

- **PCGamingWiki Files:** https://community.pcgamingwiki.com/files/file/4186-forza-horizon-5-d3dmetal-fix-for-crossover-mac/ (zip password `pcgw`)
- **GitHub Releases:** `https://github.com/Andytizer/fh5-crossover-steam-fix/releases` (or `git clone` this repo)

Each release's SHA-256 is listed on both download pages (it can't be in this README, which is inside the zip).
Check your download with `shasum -a 256 fh5-crossover-steam-fix-<version>.zip`. Report problems and results in
GitHub Issues.

## Install

Quit CrossOver completely first. Unzip the release, open Terminal in that folder, then:

```sh
sh fetch-upstream.sh                                   # checks the bundled upstream DLLs (no download)

sh make-copies.sh --app "/Applications/CrossOver Preview.app" --bottle "Steam"
#   -> "/Applications/CrossOver Preview (FH5).app" and bottle "Steam (Forza Horizon 5)"

sh setup.sh --app "/Applications/CrossOver Preview (FH5).app" --bottle "Steam (Forza Horizon 5)" --check
sh setup.sh --app "/Applications/CrossOver Preview (FH5).app" --bottle "Steam (Forza Horizon 5)"
```

Then open the **(FH5)** app, start Steam in the new bottle, and install Forza Horizon 5. When it is fully
installed (and before the first launch):

```sh
sh install-game.sh --bottle "Steam (Forza Horizon 5)"   # or: sh install-game.sh "/path/to/ForzaHorizon5"
```

`setup.sh` sets in the bottle: graphics backend D3DMetal, `HB_D3D12_REAL`, and an NVIDIA RTX 4070 identity
(`D3DM_VENDOR_ID=4318`, `D3DM_DEVICE_ID=10118`, `D3DM_DEVICE_DESCRIPTION`), which avoids the game's GPU checks.

### CrossOver 26.3

CrossOver 26.3 ships **D3DMetal 3.0**. The fix was developed on **4.0b3**, and upstream's tested setup was exactly
CrossOver 26.3's Wine plus D3DMetal 4.0b3. So `setup.sh` can put a 4.0b3 into the 26.3 copy from software you
already have:

```sh
sh make-copies.sh --app "/Applications/CrossOver.app" --bottle "Steam"
#   -> "/Applications/CrossOver (FH5).app" and bottle "Steam (Forza Horizon 5)"

sh setup.sh --app "/Applications/CrossOver (FH5).app" --bottle "Steam (Forza Horizon 5)" \
            --d3dmetal-from "/Applications/CrossOver Preview.app" --check
sh setup.sh --app "/Applications/CrossOver (FH5).app" --bottle "Steam (Forza Horizon 5)" \
            --d3dmetal-from "/Applications/CrossOver Preview.app"
```

`--d3dmetal-from` accepts a CrossOver app (it finds `lib/apple_gptk` or `lib64/apple_gptk`), an `apple_gptk`-style
folder (`external/` + `wine/`), or Apple's Game Porting Toolkit folder (`redist/lib`). Before swapping, it checks
that every function the new D3DMetal DLLs import exists in this CrossOver's Wine, and that its
`libd3dshared.dylib` exports what Wine looks up. The original D3DMetal is kept as `apple_gptk.orig`, and
`uninstall.sh` puts it back. Nothing is copied from the source app except its D3DMetal folder, and the source app
is not changed. Without `--d3dmetal-from` the fix runs on 3.0, which is untested; `setup.sh` warns.

Copy a bottle created by the same CrossOver version you patch (`setup.sh` warns if the bottle is newer than the app).
If your bottles are not in the default folder, set `CX_BOTTLE_PATH` for all scripts.

## Playing

- Always open this bottle from the **(FH5)** app copy. From the original app the proxy can't find `apd12.so`
  and the game exits; nothing breaks.
- First start can sit on a black screen for minutes while shaders build.
- Click **Ignore Warning** on the FH302 driver-version warning (upstream known issue).
- DLSS is mapped to MetalFX. Keep Frame Generation off. Keep Steam Cloud on.
- Logs: add `"HB_DEBUG" = "1"` to the bottle's `[EnvironmentVariables]`. Logs go to `C:\highball\logs`.
  The other upstream `HB_*` switches work the same way, without the `NOTPROTON_ENV_` prefix.
- Xbox sign-in: see upstream README step 11 (`upstream/source/README.md`). Put `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` in `cxbottle.conf`.

## Updates and undo

- Both app copies share a bundle ID. If CrossOver updates or replaces the copy, the app-side changes are gone:
  re-run `setup.sh`. It detects what is already applied and checks the new ntdll.
- The app copy's code-signature seal is broken by the edits. macOS still opens it (tested on macOS 27).
- Undo: `sh uninstall.sh --app "<app copy>" --bottle "<bottle>"`. Or delete the app copy and the bottle copy
  (copy your saves out of the bottle first).

## Known limits

- **ws2_32 wrapper fit.** The upstream wrapper was generated from Highball's Wine (CrossOver 26.3 based). On
  **26.3 it fits exactly**. CrossOver Preview's `ws2_32` has two more exports (`WSCEnumProtocols32`,
  `WSCInstallProvider64_32`, LSP-installer functions), and the ordinals above 117 shift. All classic ordinals
  (1–117) and every name the wrapper forwards match. `setup.sh --check` reports this for your version. A perfect
  fit on Preview needs rebuilding `upstream/source/tools/ws2_32-netfix` against its `ws2_32.dll` (llvm-mingw).
- **D3DMetal version.** Upstream was tuned on D3DMetal 4.0b3. `setup.sh` warns if the D3DMetal in use is another
  version. On 26.3 use `--d3dmetal-from`. The swap is verified statically (imports, exported symbols), not yet
  in game.
- **Unwind fix.** CrossOver 27's Wine may already handle NULL pointers there; the patch is harmless if so.
- Everything else in the upstream "Known issues" applies.

## Files

| File | Purpose |
|---|---|
| `fetch-upstream.sh` | Checks the bundled `upstream/d3d12.dll` and `upstream/ws2_32.dll` against `upstream/SHA256SUMS` |
| `upstream/` | Upstream's prebuilt DLLs and complete source at commit `ebd20dbe` (`upstream/README.md`) |
| `make-copies.sh` | Copies the app and the bottle (new BottleID) |
| `setup.sh` | Inspects (`--check`) and applies the fix to the app copy and bottle. Idempotent; keeps `.orig` backups |
| `install-game.sh` | Copies the proxy into the game folder |
| `uninstall.sh` | Reverses setup and install |
| `build-release.sh` | Maintainers: builds `dist/fh5-crossover-steam-fix-<VERSION>.zip` and its SHA-256 (not in the zip) |
| `tools/patch_unwind_cx.pl` | Address-finding port of upstream `tools/ntdll-unwindfix/patch_unwind.pl` |
| `tools/pe.pl` | PE helper: export listing, export rename (port of upstream `pe_tools.py rename-export`), wrapper/export comparison |

## Credits and licence

- **fh5-d3dmetal-fix** by xvferxedd: the proxy, the ws2_32 wrapper, the unwind fix and the research.
  GPL-3.0. Its repository (github.com/xvferxedd/fh5-d3dmetal-fix) is no longer online; a copy is in `upstream/`.
- **Highball** (tsshim, which the proxy is built on) by Gauthier Piarrette, GPL-3.0.
  https://github.com/gauthierpiarrette/highball
- Upstream credits MACxus (FH5 profile), Bridgeplay and whyAm-i's FH4 Mac patches.

This repository is licensed **GPL-3.0** (see `LICENSE`), as it contains code derived from the projects above.
The upstream DLLs are redistributed unchanged under GPL-3.0, with their complete source in `upstream/source/`
(build with `upstream/source/build.sh` and `upstream/source/tools/ws2_32-netfix/build.sh`).
