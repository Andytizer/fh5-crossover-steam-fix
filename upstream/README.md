# Bundled upstream: xvferxedd/fh5-d3dmetal-fix

The repository `github.com/xvferxedd/fh5-d3dmetal-fix` and its author's account were no longer available in
November 2026. This folder keeps a copy, as the GPL-3.0 allows, so the fix can still be installed and rebuilt.

- `d3d12.dll`, `ws2_32.dll`: the prebuilt binaries from upstream `bin/`, unchanged. `SHA256SUMS` matches the
  hashes upstream published in `bin/*.sha256`.
- `source/`: the complete upstream tree at commit `ebd20dbe6572751ff94f6c7e90e5cebf7d96a0ce` (2026-11-05),
  unchanged, except that `source/bin/*.dll` were removed because they are the two files above.
  This is the Corresponding Source for both DLLs: `source/build.sh` builds `d3d12.dll` and
  `source/tools/ws2_32-netfix/build.sh` builds `ws2_32.dll` (llvm-mingw).

Licence: GPL-3.0 (`source/LICENSE`). `source/src/d3d12.c` and `source/src/d3d12.def` come from Highball's tsshim
by Gauthier Piarrette (GPL-3.0), see `source/src/ORIGIN.md`. All credit for the fix belongs to xvferxedd and the
people credited in `source/README.md`. Links in `source/` to the upstream repository no longer work.
