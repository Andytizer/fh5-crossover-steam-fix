<!-- Paste into the PCGamingWiki Files form (update the existing file 4186 with a new version). -->

**Title:** Forza Horizon 5 – D3DMetal fix for CrossOver Mac

**Version:** 1.0.1

**What's new in 1.0.1:** the original fh5-d3dmetal-fix repository by xvferxedd is no longer online, so 1.0.0 could
not download its two DLLs. 1.0.1 includes them (unchanged) together with their complete GPL-3.0 source.
Nothing else about the install changed.

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
`setup.sh --d3dmetal-from` swaps in 4.0b3 from your own CrossOver Preview (checked for compatibility first,
original kept). In-game results are still being collected. Please report yours on GitHub.

**Requirements:** Apple Silicon Mac, CrossOver, a Steam bottle, your own Steam copy of Forza Horizon 5.
Uses only tools built into macOS (no Python, Docker or Xcode).

**Install:** unzip (password `pcgw`), open Terminal in the folder, follow README.md:

    sh fetch-upstream.sh
    sh make-copies.sh --app "/Applications/CrossOver Preview.app" --bottle "Steam"
    sh setup.sh --app "/Applications/CrossOver Preview (FH5).app" --bottle "Steam (Forza Horizon 5)" --check
    sh setup.sh --app "/Applications/CrossOver Preview (FH5).app" --bottle "Steam (Forza Horizon 5)"
    # install the game in the new bottle, then:
    sh install-game.sh --bottle "Steam (Forza Horizon 5)"

    # CrossOver 26.3: copy "/Applications/CrossOver.app" instead, and add to both setup.sh lines:
    #   --d3dmetal-from "/Applications/CrossOver Preview.app"

**Contents:** shell and Perl scripts, README, CHANGELOG, LICENSE, and `upstream/`: the two fh5-d3dmetal-fix DLLs
(`d3d12.dll` proxy, `ws2_32.dll` network fix, unchanged, hash-checked by `fetch-upstream.sh`) with their complete
source. No game, CrossOver, Apple or Microsoft files.

**Archive password:** `pcgw`

**File:** `fh5-crossover-steam-fix-1.0.1-pcgw.zip`, SHA-256
`e63a9c39738ebe4ede20154d9b5f3e7bc072e980b7f550225e2b26e2a5eb9fcb`.
Its contents are identical to `fh5-crossover-steam-fix-1.0.1.zip` on the GitHub release page (SHA-256
`de0ba6fee3184c6fcb6480206ffd5c3ba3a493c6b1750d1e12a8ba72ed8a2274`).

**Source, issues and documentation:** https://github.com/Andytizer/fh5-crossover-steam-fix

**Credits:** fh5-d3dmetal-fix by xvferxedd (original repository no longer online; preserved under GPL-3.0 in this
release), built on Highball's tsshim by Gauthier Piarrette (https://github.com/gauthierpiarrette/highball).
Licensed GPL-3.0. Not affiliated with CodeWeavers, Apple, Microsoft or Playground Games. Use at your own risk.
