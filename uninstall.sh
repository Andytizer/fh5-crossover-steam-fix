#!/bin/sh
# Reverses setup.sh and install-game.sh using the .orig backups they made.
#
#   sh uninstall.sh --app "/Applications/CrossOver (FH5).app" --bottle "Steam (Forza Horizon 5)" [--game DIR]
#
# Without --game, the proxy is removed from the bottle's default Steam library if it is there.
# Restoring user.reg.orig also drops registry changes made since setup, so the overrides section is removed
# from the current user.reg instead. (Simplest full undo: delete the app copy and the bottle copy.)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
APP=; BOTTLE=; GAME=
die() { echo "ERROR: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:?}"; shift 2;; --bottle) BOTTLE="${2:?}"; shift 2;; --game) GAME="${2:?}"; shift 2;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0;; *) die "unknown argument: $1";;
  esac
done
[ -n "$APP" ] && [ -n "$BOTTLE" ] || die "--app and --bottle are required"
pgrep -x wineserver >/dev/null || pgrep -f 'wineserver-(x86|arm64)' >/dev/null && die "quit CrossOver and all bottles first"
S="${APP%/}/Contents/SharedSupport/CrossOver"; B="${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}/$BOTTLE"
W="$S/lib/wine/x86_64-windows"; U="$S/lib/wine/x86_64-unix"
SYS="$B/drive_c/windows/system32"
[ -n "$GAME" ] || GAME="$B/drive_c/Program Files (x86)/Steam/steamapps/common/ForzaHorizon5"

if [ -f "$GAME/d3d12.dll" ] && cmp -s "$GAME/d3d12.dll" "$HERE/upstream/d3d12.dll"; then
  rm "$GAME/d3d12.dll"; echo "removed proxy from game folder"
  [ -e "$GAME/d3d12.dll.orig" ] && mv "$GAME/d3d12.dll.orig" "$GAME/d3d12.dll" && echo "restored game d3d12.dll.orig"
fi
if [ -d "$B" ]; then
  [ -e "$SYS/ws2_32.dll.orig" ] && mv "$SYS/ws2_32.dll.orig" "$SYS/ws2_32.dll" && echo "restored system32/ws2_32.dll"
  rm -f "$SYS/apd12.dll" "$SYS/ws2_o.dll"
  [ -e "$B/cxbottle.conf.orig" ] && mv "$B/cxbottle.conf.orig" "$B/cxbottle.conf" && echo "restored cxbottle.conf"
  perl -0777 -i -pe 's/\n\[Software\\\\Wine\\\\AppDefaults\\\\ForzaHorizon5\.exe\\\\DllOverrides\][^\n]*\n(?:[^\[\n][^\n]*\n)*//' "$B/user.reg" && echo "removed per-exe overrides from user.reg"
  rm -f "$B/user.reg.orig"
fi
if [ -d "$S" ]; then
  [ -e "$W/ntdll.dll.orig" ] && mv "$W/ntdll.dll.orig" "$W/ntdll.dll" && echo "restored app ntdll.dll"
  rm -f "$W/ws2_o.dll" "$U/ws2_o.so"
  for G in "$S/lib/apple_gptk" "$S/lib64/apple_gptk"; do
    if [ -f "$G/.fh5-d3dmetal-source" ] && [ -d "$G.orig" ]; then rm -rf "$G"; mv "$G.orig" "$G"; echo "restored original D3DMetal in ${G#"$S/"}"
    elif [ -d "$G" ]; then rm -f "$G/wine/x86_64-windows/apd12.dll" "$G/wine/x86_64-unix/apd12.so"; fi
  done
  echo "removed apd12 / ws2_o from app"
fi
echo "done"
