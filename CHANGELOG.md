# Changelog

## 1.0.1 — 2026-11-10

- The upstream repository (xvferxedd/fh5-d3dmetal-fix) and its author's account are gone, so `fetch-upstream.sh`
  could no longer download the DLLs. The release now bundles upstream's `d3d12.dll` and `ws2_32.dll` (unchanged,
  same SHA-256 as 1.0.0 checked) and upstream's complete source at commit `ebd20dbe` in `upstream/source/`, as the
  GPL-3.0 requires. `fetch-upstream.sh` now only verifies the bundled files.
- README links the PCGamingWiki download page.
- `install-game.sh` and `make-copies.sh` help no longer prints the `set -eu` line.
- No change to what `setup.sh`, `install-game.sh` or `uninstall.sh` install.

## 1.0.0 — 2026-11-08

First release.

- Applies xvferxedd/fh5-d3dmetal-fix (upstream commit `ebd20dbe`) to a copy of CrossOver and a copy of a Steam bottle.
- Supports CrossOver Preview (`lib/apple_gptk`, D3DMetal 4.0b3) and CrossOver 26.3 (`lib64/apple_gptk`, D3DMetal 3.0).
- `setup.sh --d3dmetal-from`: swaps a D3DMetal from another CrossOver app, an `apple_gptk` folder or Apple's Game
  Porting Toolkit into the app copy (e.g. 4.0b3 into 26.3), after checking imports and `libd3dshared` symbols.
  `uninstall.sh` restores the original.
- `setup.sh --check`: reports ntdll support, D3DMetal version, `ws2_32` wrapper fit and bottle/app version without
  changing anything.
- `tools/patch_unwind_cx.pl`: `RtlVirtualUnwind2` NULL-pointer fix that finds its addresses in the PE (no fixed RVAs).
  Verified patchable on Preview 20261015 (hook 0x66610) and 26.3.0 (hook 0x38120).
- `fetch-upstream.sh`: downloads the upstream DLLs at the pinned commit and checks their hashes. No binaries are bundled.
- `make-copies.sh`, `install-game.sh`, `uninstall.sh`. All scripts honor `CX_BOTTLE_PATH`.
- Tested: CrossOver Preview 20261015 on a real install; CrossOver 26.3.0 by a full setup → uninstall cycle on a copy
  (restores all files byte for byte). macOS 27.
