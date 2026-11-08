<!-- Paste into the PCGamingWiki Files upload form. Fill in the two URLs and the SHA-256 from dist/*.sha256. -->

**Title:** Forza Horizon 5 – D3DMetal fix for CrossOver (macOS)

**Category:** Unofficial patches / Tools (Forza Horizon 5)

**Version:** 1.0.0

**Description:**

Install scripts that let Forza Horizon 5 (Steam) run in **CrossOver** on Apple Silicon Macs with D3DMetal,
using the fixes from xvferxedd's **fh5-d3dmetal-fix**:

- Fixes `Fatal Error 0x800705AA` in free roam and at the 4th intro ride (descriptor-stride fix)
- Fixes black or missing objects (dual-source blend rewrite)
- Fixes a crash at the loading-tips screen (ntdll `RtlVirtualUnwind2` patch, ported to CrossOver)
- Online (Horizon Life / Horizon Open) via the `ws2_32` network fix
- Presents an NVIDIA GPU identity to avoid the game's GPU checks; DLSS maps to MetalFX

The scripts modify a **copy** of CrossOver and a **copy** of your Steam bottle, never the originals.
`setup.sh --check` inspects your CrossOver version first and changes nothing.

**Supported:** CrossOver Preview 20261015 (D3DMetal 4.0b3) and CrossOver 26.3. CrossOver 26.3 ships D3DMetal 3.0;
`setup.sh --d3dmetal-from` can swap in 4.0b3 from your own CrossOver Preview or Apple Game Porting Toolkit install
(checked for compatibility first, original kept). Tested on macOS 27: Preview on a real install, 26.3 by a full
install/uninstall cycle on a copy. In-game results on 26.3 are still being collected. Please report yours on GitHub.

**Requirements:** Apple Silicon Mac, CrossOver, a Steam bottle, your own Steam copy of Forza Horizon 5.
Uses only tools built into macOS (no Python, Docker or Xcode).

**Install:** unzip, open Terminal in the folder, follow README.md:

    sh fetch-upstream.sh
    sh make-copies.sh --app "/Applications/CrossOver Preview.app" --bottle "Steam"
    sh setup.sh --app "/Applications/CrossOver Preview (FH5).app" --bottle "Steam (Forza Horizon 5)" --check
    sh setup.sh --app "/Applications/CrossOver Preview (FH5).app" --bottle "Steam (Forza Horizon 5)"
    # install the game in the new bottle, then:
    sh install-game.sh --bottle "Steam (Forza Horizon 5)"

    # CrossOver 26.3: copy "/Applications/CrossOver.app" instead, and add to both setup.sh lines:
    #   --d3dmetal-from "/Applications/CrossOver Preview.app"

**Contents:** shell and Perl scripts, README, CHANGELOG, LICENSE. No game, CrossOver, Apple or Microsoft files.
The two upstream DLLs are not included: `fetch-upstream.sh` downloads them from the upstream GitHub repository
at a pinned commit and verifies their SHA-256.

**SHA-256 (fh5-crossover-steam-fix-1.0.0.zip):** `fe080cd861045179623d89a6e844229344d945abd496524ff510ef5054df9a90`

**Source, issues and documentation:** `https://github.com/Andytizer/fh5-crossover-steam-fix`

**Credits:** fh5-d3dmetal-fix by xvferxedd (https://github.com/xvferxedd/fh5-d3dmetal-fix), built on Highball's
tsshim by Gauthier Piarrette (https://github.com/gauthierpiarrette/highball). Licensed GPL-3.0.
Not affiliated with CodeWeavers, Apple, Microsoft or Playground Games. Use at your own risk.
