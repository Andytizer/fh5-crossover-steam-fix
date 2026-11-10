#!/bin/sh
# Builds dist/fh5-crossover-steam-fix-<VERSION>.zip for upload (PCGamingWiki Files / GitHub Releases).
# The zip holds the scripts, LICENSE, docs and upstream/ (the two upstream DLLs and their complete source).
set -eu
cd "$(dirname "$0")"
VER="$(cat VERSION)"
NAME="fh5-crossover-steam-fix-$VER"
OUT="dist/$NAME.zip"
FILES="README.md CHANGELOG.md LICENSE VERSION setup.sh install-game.sh make-copies.sh uninstall.sh fetch-upstream.sh
       tools/pe.pl tools/patch_unwind_cx.pl upstream/SHA256SUMS upstream/README.md upstream/d3d12.dll upstream/ws2_32.dll
       $(find upstream/source -type f ! -name .DS_Store | sort)"
for f in $FILES; do test -f "$f" || { echo "missing $f" >&2; exit 1; }; done
for f in *.sh; do sh -n "$f"; done
perl -c tools/pe.pl >/dev/null 2>&1 && perl -c tools/patch_unwind_cx.pl >/dev/null 2>&1
rm -rf "dist/$NAME" "$OUT"; mkdir -p "dist/$NAME"
for f in $FILES; do mkdir -p "dist/$NAME/$(dirname "$f")"; cp "$f" "dist/$NAME/$f"; done
(cd upstream && shasum -a 256 -c SHA256SUMS >/dev/null)
chmod 755 "dist/$NAME"/*.sh
(cd dist && TZ=UTC find "$NAME" -exec touch -t 202601010000 {} + && zip -qrX "$NAME.zip" "$NAME")
rm -rf "dist/$NAME"
shasum -a 256 "$OUT" | tee "$OUT.sha256"
unzip -l "$OUT" | tail -n +4 | sed '$d' | sed '$d' | awk '{print "  " $4}'
