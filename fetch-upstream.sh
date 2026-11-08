#!/bin/sh
# Downloads the two prebuilt GPL-3.0 DLLs from xvferxedd/fh5-d3dmetal-fix at a pinned commit and checks their
# SHA-256. This repo does not redistribute them; their source is at the same commit:
#   https://github.com/xvferxedd/fh5-d3dmetal-fix/tree/ebd20dbe6572751ff94f6c7e90e5cebf7d96a0ce
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
COMMIT=ebd20dbe6572751ff94f6c7e90e5cebf7d96a0ce
BASE="https://raw.githubusercontent.com/xvferxedd/fh5-d3dmetal-fix/$COMMIT/bin"
cd "$HERE/upstream"
for f in d3d12.dll ws2_32.dll; do
  curl -fsSL -o "$f.part" "$BASE/$f"
  mv "$f.part" "$f"
done
shasum -a 256 -c SHA256SUMS
echo "ok: upstream binaries from commit ${COMMIT%"${COMMIT#????????}"}"
