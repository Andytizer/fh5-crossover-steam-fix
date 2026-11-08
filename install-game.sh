#!/bin/sh
# Adds the one file the fix needs in the game folder: the upstream d3d12.dll proxy (unchanged).
#
#   sh install-game.sh --bottle "Steam (Forza Horizon 5)"     (game in the bottle's default Steam library)
#   sh install-game.sh "/path/to/steamapps/common/ForzaHorizon5"
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "ERROR: $*" >&2; exit 1; }
case "${1:-}" in
  --bottle) GAME="${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}/${2:?bottle name}/drive_c/Program Files (x86)/Steam/steamapps/common/ForzaHorizon5";;
  ""|-h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) GAME="$1";;
esac
test -f "$GAME/ForzaHorizon5.exe" || die "no ForzaHorizon5.exe in $GAME (still downloading? other library? pass the folder path)"
pgrep -f 'ForzaHorizon5.exe' >/dev/null && die "the game is running; quit it first"
(cd "$HERE/upstream" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) || die "upstream/ missing or hash mismatch: run sh fetch-upstream.sh"
if [ -e "$GAME/d3d12.dll" ] && ! cmp -s "$GAME/d3d12.dll" "$HERE/upstream/d3d12.dll"; then
  [ -e "$GAME/d3d12.dll.orig" ] && die "$GAME/d3d12.dll.orig already exists"
  cp -p "$GAME/d3d12.dll" "$GAME/d3d12.dll.orig"
fi
cp "$HERE/upstream/d3d12.dll" "$GAME/d3d12.dll"
shasum -a 256 "$GAME/d3d12.dll"
echo "ok: proxy installed in $GAME"
echo "(a stock install has no d3d12.dll in the game folder; deleting it undoes this. Steam 'Verify files' leaves it alone.)"
