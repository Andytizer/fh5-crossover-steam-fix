#!/bin/sh
# Applies the FH5 D3DMetal fix (xvferxedd/fh5-d3dmetal-fix) to a CrossOver app COPY and one bottle.
#
#   sh setup.sh --app "/Applications/CrossOver (FH5).app" --bottle "Steam (Forza Horizon 5)" [--check]
#
#   --check                 inspect and report only; change nothing
#   --d3dmetal-from SRC     replace the app copy's D3DMetal with the one in SRC: another CrossOver app (e.g.
#                           CrossOver Preview, D3DMetal 4.0b3) or an apple_gptk-style folder (external/ + wine/)
#   --allow-original-app    permit patching an app named exactly CrossOver.app / CrossOver Preview.app
#
# Changes (each replaced file is kept once as <file>.orig; GPTK = lib/apple_gptk or lib64/apple_gptk):
#   app:    lib/wine/x86_64-windows/ntdll.dll           RtlVirtualUnwind2 NULL-pointer fix
#           GPTK (only with --d3dmetal-from)            swapped D3DMetal; original kept as GPTK.orig
#           GPTK/wine/x86_64-*/apd12.{dll,so}           the real D3DMetal d3d12 under another name
#           lib/wine/x86_64-*/ws2_o.{dll,so}             Wine ws2_32 under another name (for the online fix)
#   bottle: system32/{apd12,ws2_o,ws2_32}.dll, cxbottle.conf [EnvironmentVariables], user.reg per-exe overrides
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
APP=; BOTTLE=; CHECK=0; ALLOW_ORIG=0; WARN=0; DSRC=
die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "   WARNING: $*"; WARN=$((WARN + 1)); }
sha()  { shasum -a 256 "$1" | cut -d' ' -f1; }
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }
# find the apple_gptk folder of a CrossOver app root ($1 = .../SharedSupport/CrossOver)
gptk_of() { for g in lib/apple_gptk lib64/apple_gptk; do [ -f "$1/$g/wine/x86_64-windows/d3d12.dll" ] && { echo "$1/$g"; return 0; }; done; return 1; }
d3dm_ver() { plutil -extract CFBundleShortVersionString raw "$1/external/D3DMetal.framework/Resources/Info.plist" 2>/dev/null || echo unknown; }
# every import of the D3DMetal PE DLLs in $1 must exist in the Wine DLLs in $2; prints problems, returns count
check_imports() {
  n=0
  for f in "$1"/wine/x86_64-windows/*.dll; do
    for imp in $(perl "$PEPL" imports "$f"); do
      dll=${imp%%!*}; fn=${imp#*!}
      [ -f "$1/wine/x86_64-windows/$dll" ] && continue        # provided by D3DMetal itself
      if [ ! -f "$2/$dll" ]; then echo "             unresolved: ${f##*/} needs $dll"; n=$((n + 1)); continue; fi
      perl "$PEPL" exports "$2/$dll" | awk '{print $2}' | grep -qx -- "$fn" || { echo "             unresolved: ${f##*/} needs $imp"; n=$((n + 1)); }
    done
  done
  return $n
}
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:?}"; shift 2;;
    --bottle) BOTTLE="${2:?}"; shift 2;;
    --check) CHECK=1; shift;;
    --d3dmetal-from) DSRC="${2:?}"; shift 2;;
    --allow-original-app) ALLOW_ORIG=1; shift;;
    -h|--help) usage; exit 0;;
    *) usage; die "unknown argument: $1";;
  esac
done
[ -n "$APP" ] && [ -n "$BOTTLE" ] || { usage; die "--app and --bottle are required"; }
APP="${APP%/}"
S="$APP/Contents/SharedSupport/CrossOver"
B="${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}/$BOTTLE"
W="$S/lib/wine/x86_64-windows";  U="$S/lib/wine/x86_64-unix"
SYS="$B/drive_c/windows/system32"
PEPL="$HERE/tools/pe.pl"

echo "== Inspect"
test -d "$S" || die "not a CrossOver app: $APP"
VER="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
NAME="$(plutil -extract CFBundleName raw "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
echo "   app:      $APP ($NAME $VER)"
case "${APP##*/}" in
  "CrossOver.app"|"CrossOver Preview.app")
    [ "$ALLOW_ORIG" = 1 ] || [ "$CHECK" = 1 ] || die "this looks like your original app; patch a copy (make-copies.sh) or pass --allow-original-app";;
esac
test -f "$B/cxbottle.conf" || die "no bottle '$BOTTLE' in $(dirname "$B")"
grep -q '^"WineArch" = "win64"' "$B/cxbottle.conf" || warn "bottle is not win64"
BVER="$(sed -n 's/^"Version" = "\(.*\)"/\1/p' "$B/cxbottle.conf" | head -1)"
AVER="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || echo 0)"
echo "   bottle:   $B (made by CrossOver ${BVER:-?})"
if [ -n "$BVER" ] && [ "${BVER%%.*}" -gt "${AVER%%.*}" ] 2>/dev/null; then
  warn "bottle was made by a newer CrossOver ($BVER) than this app ($AVER); copy a bottle created with this CrossOver version"
fi

# ntdll
set +e; NT_MSG="$(perl "$HERE/tools/patch_unwind_cx.pl" "$W/ntdll.dll" --check 2>&1)"; NT_RC=$?; set -e
echo "   ntdll:    $NT_MSG"
case $NT_RC in 0|3) ;; *) die "this CrossOver's ntdll.dll is not supported by the unwind patcher (see message above)";; esac

# D3DMetal
G="$(gptk_of "$S")" || die "no D3DMetal (lib/apple_gptk or lib64/apple_gptk) in $S: unsupported CrossOver layout"
GW="$G/wine/x86_64-windows"; GU="$G/wine/x86_64-unix"
test -e "$GU/d3d12.so" || die "$GU/d3d12.so missing"
D3DM_VER="$(d3dm_ver "$G")"
SWAPPED=; [ -f "$G/.fh5-d3dmetal-source" ] && SWAPPED="$(cat "$G/.fh5-d3dmetal-source")"
echo "   D3DMetal: $D3DM_VER (${G#"$S/"})${SWAPPED:+, swapped in from $SWAPPED}"
DSRC_G=
if [ -n "$DSRC" ]; then
  DSRC="${DSRC%/}"
  if [ -d "$DSRC/Contents/SharedSupport/CrossOver" ]; then DSRC_G="$(gptk_of "$DSRC/Contents/SharedSupport/CrossOver")" || die "no D3DMetal in $DSRC"
  elif [ -f "$DSRC/wine/x86_64-windows/d3d12.dll" ] && [ -d "$DSRC/external" ]; then DSRC_G="$DSRC"
  elif [ -f "$DSRC/redist/lib/wine/x86_64-windows/d3d12.dll" ]; then DSRC_G="$DSRC/redist/lib"   # Apple GPTK layout
  else die "--d3dmetal-from: no D3DMetal found in $DSRC"; fi
  [ "$(cd "$DSRC_G" && pwd -P)" = "$(cd "$G" && pwd -P)" ] && die "--d3dmetal-from points at this app's own D3DMetal"
  SRC_VER="$(d3dm_ver "$DSRC_G")"
  echo "   swap in:  D3DMetal $SRC_VER from $DSRC_G"
  set +e; check_imports "$DSRC_G" "$W"; NBAD=$?; set -e
  [ "$NBAD" = 0 ] && echo "             all imports of its DLLs resolve against this Wine" \
                  || die "D3DMetal from $DSRC_G needs $NBAD function(s) this Wine lacks; not compatible"
  for sym in register_non_native_code_region supports_non_native_code_regions __wine_unix_call_funcs; do
    grep -aq "_$sym" "$DSRC_G/external/libd3dshared.dylib" || warn "its libd3dshared.dylib lacks $sym (this Wine may not load it)"
  done
  EFF_VER="$SRC_VER"
else
  EFF_VER="$D3DM_VER"
fi
if [ "$EFF_VER" != "4.0b3" ]; then
  warn "the fix was tuned on D3DMetal 4.0b3; $EFF_VER is untested.$( [ -z "$DSRC" ] && echo " Consider --d3dmetal-from with a 4.0b3 source (e.g. your CrossOver Preview app)")"
fi
if grep -q '^"CX_GRAPHICS_BACKEND_VERSION"' "$B/cxbottle.conf"; then
  warn "bottle sets CX_GRAPHICS_BACKEND_VERSION; it may select a D3DMetal other than ${G#"$S/"}"
fi

# upstream binaries
for f in d3d12.dll ws2_32.dll; do test -f "$HERE/upstream/$f" || die "upstream/$f missing: download the release zip again"; done
(cd "$HERE/upstream" && shasum -a 256 -c SHA256SUMS >/dev/null) || die "upstream/ hash mismatch: download the release zip again"

# ws2_32 wrapper fit
set +e; WS_MSG="$(perl "$PEPL" compare-wrapper "$HERE/upstream/ws2_32.dll" "$W/ws2_32.dll")"; WS_RC=$?; set -e
echo "   ws2_32:   $(echo "$WS_MSG" | tail -1 | sed 's/^summary: //')"
case $WS_RC in
  0) ;;
  1) echo "$WS_MSG" | grep '^EXTRA' | sed 's/^/             /'
     echo "             (extras are unreachable through the wrapper; fine for FH5 unless something imports them)";;
  *) echo "$WS_MSG" | grep -E '^(MISSING|ORDINAL)' | sed 's/^/             /'
     warn "ws2_32 wrapper does not fit this Wine; online fix may break. Rebuild it from upstream tools/ws2_32-netfix";;
esac

if pgrep -x wineserver >/dev/null || pgrep -f 'wineserver-(x86|arm64)' >/dev/null; then
  if [ "$CHECK" = 1 ]; then warn "a wineserver is running (quit CrossOver before applying)"
  else die "a wineserver is running; quit CrossOver and all bottles first"; fi
fi

if [ "$CHECK" = 1 ]; then echo; echo "Check finished: $WARN warning(s). Nothing was changed."; exit 0; fi

if [ -n "$DSRC_G" ]; then
  echo "== 0. swap D3DMetal: $SRC_VER from $DSRC_G"
  if [ -n "$SWAPPED" ] && [ "$SWAPPED" = "$DSRC_G ($SRC_VER)" ]; then echo "   already swapped from this source"
  else
    if [ -e "$G.orig" ]; then
      [ -n "$SWAPPED" ] || die "$G.orig exists but $G is not a swapped copy; resolve by hand"
      rm -rf "$G"                                   # replacing an earlier swap; the true original stays in .orig
    else
      mv "$G" "$G.orig"
    fi
    ditto "$DSRC_G" "$G"
    rm -f "$G/wine/x86_64-windows/apd12.dll" "$G/wine/x86_64-unix/apd12.so"   # source may carry its own; rebuilt below
    echo "$DSRC_G ($SRC_VER)" > "$G/.fh5-d3dmetal-source"
    echo "   ${G#"$S/"} is now D3DMetal $(d3dm_ver "$G"); original kept as ${G#"$S/"}.orig"
  fi
fi

echo "== 1. ntdll RtlVirtualUnwind2 NULL-pointer fix"
if [ "$NT_RC" = 3 ]; then echo "   already applied"
else
  [ -e "$W/ntdll.dll.orig" ] && die "$W/ntdll.dll.orig exists but ntdll.dll is unpatched; resolve by hand"
  cp -p "$W/ntdll.dll" "$W/ntdll.dll.orig"
  perl "$HERE/tools/patch_unwind_cx.pl" "$W/ntdll.dll.orig" "$W/ntdll.dll.new" | sed 's/^/   /'
  mv "$W/ntdll.dll.new" "$W/ntdll.dll"
fi

echo "== 2. apd12.dll / apd12.so (real D3DMetal d3d12)"
if [ ! -e "$GW/apd12.dll" ] || [ "$(perl "$PEPL" export-name "$GW/apd12.dll")" != apd12.dll ]; then
  cp -p "$GW/d3d12.dll" "$GW/apd12.dll"
  perl "$PEPL" rename-export "$GW/apd12.dll" apd12.dll >/dev/null
fi
[ -L "$GU/apd12.so" ] || ln -s "$(readlink "$GU/d3d12.so" || echo d3d12.so)" "$GU/apd12.so"
test -e "$GU/apd12.so" || die "apd12.so does not resolve"
echo "   apd12.dll export name: $(perl "$PEPL" export-name "$GW/apd12.dll"); apd12.so -> $(readlink "$GU/apd12.so")"

echo "== 3. ws2_o.dll / ws2_o.so (Wine ws2_32)"
if [ ! -e "$W/ws2_o.dll" ] || [ "$(perl "$PEPL" export-name "$W/ws2_o.dll")" != ws2_o.dll ]; then
  cp -p "$W/ws2_32.dll" "$W/ws2_o.dll"
  perl "$PEPL" rename-export "$W/ws2_o.dll" ws2_o.dll >/dev/null
fi
[ -L "$U/ws2_o.so" ] || ln -s ws2_32.so "$U/ws2_o.so"
test -e "$U/ws2_o.so" || die "ws2_o.so does not resolve"
echo "   ws2_o.dll export name: $(perl "$PEPL" export-name "$W/ws2_o.dll")"

echo "== 4. bottle system32"
cp -p "$GW/apd12.dll" "$SYS/apd12.dll"
cp -p "$W/ws2_o.dll" "$SYS/ws2_o.dll"
if [ ! -e "$SYS/ws2_32.dll.orig" ]; then cp -p "$SYS/ws2_32.dll" "$SYS/ws2_32.dll.orig"; fi
cp "$HERE/upstream/ws2_32.dll" "$SYS/ws2_32.dll"
echo "   apd12.dll, ws2_o.dll, ws2_32.dll (wrapper $(sha "$SYS/ws2_32.dll" | cut -c1-8))"

echo "== 5. cxbottle.conf environment"
C="$B/cxbottle.conf"
[ -e "$C.orig" ] || cp -p "$C" "$C.orig"
perl -i -pe '
  if (/^\[EnvironmentVariables\]/) { $inenv = 1; print; for (
      ["CX_GRAPHICS_BACKEND","d3dmetal"], ["HB_D3D12_REAL","C:/windows/system32/apd12.dll"],
      ["D3DM_VENDOR_ID","4318"], ["D3DM_DEVICE_ID","10118"], ["D3DM_DEVICE_DESCRIPTION","NVIDIA GeForce RTX 4070"]) {
        print "\"$_->[0]\" = \"$_->[1]\"\n" } $_ = ""; next }
  $inenv = 0 if /^\[/;
  $_ = "" if $inenv && /^"(CX_GRAPHICS_BACKEND|HB_D3D12_REAL|D3DM_VENDOR_ID|D3DM_DEVICE_ID|D3DM_DEVICE_DESCRIPTION)"/;
' "$C"
grep -q '^"HB_D3D12_REAL"' "$C" || die "cxbottle.conf has no [EnvironmentVariables] section"
sed -n '/^\[EnvironmentVariables\]/,/^\[/p' "$C" | grep '^"' | sed 's/^/   /'

echo "== 6. per-exe DLL overrides for ForzaHorizon5.exe"
R="$B/user.reg"
[ -e "$R.orig" ] || cp -p "$R" "$R.orig"
KEY='[Software\\Wine\\AppDefaults\\ForzaHorizon5.exe\\DllOverrides]'   # user.reg stores \\ literally
if grep -qF 'AppDefaults\\ForzaHorizon5.exe\\DllOverrides]' "$R"; then
  echo "   already present"
else
  printf '\n%s %s\n"d3d12"="native"\n"ws2_32"="native,builtin"\n' "$KEY" "$(date +%s)" >> "$R"
fi
grep -A3 -F 'ForzaHorizon5.exe\\DllOverrides]' "$R" | grep -v '^#time' | sed 's/^/   /'

echo
echo "Done ($WARN warning(s)). Launch this bottle only from: $APP"
echo "After Forza Horizon 5 is installed:  sh \"$HERE/install-game.sh\" --bottle \"$BOTTLE\""
