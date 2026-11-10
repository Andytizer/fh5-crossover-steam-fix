#!/bin/sh
# Checks the bundled upstream DLLs (upstream/d3d12.dll, upstream/ws2_32.dll) against upstream/SHA256SUMS.
# Since 1.0.1 they ship in the release: the upstream repository (xvferxedd/fh5-d3dmetal-fix) is gone, so nothing
# is downloaded any more. Their source is in upstream/source/ (see upstream/README.md).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/upstream"
for f in d3d12.dll ws2_32.dll; do
  test -f "$f" || { echo "ERROR: upstream/$f missing: download the full release zip again" >&2; exit 1; }
done
shasum -a 256 -c SHA256SUMS || { echo "ERROR: hash mismatch: download the full release zip again" >&2; exit 1; }
echo "ok: bundled upstream binaries (commit ebd20dbe) verified"
