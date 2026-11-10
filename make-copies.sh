#!/bin/sh
# Makes the two copies the fix is applied to, so your original CrossOver app and bottle stay untouched.
#
#   sh make-copies.sh --app "/Applications/CrossOver.app" --bottle "Steam" \
#                     [--new-app "/Applications/CrossOver (FH5).app"] [--new-bottle "Steam (Forza Horizon 5)"]
#
# Either copy can be skipped with --no-app-copy / --no-bottle-copy. Nothing existing is overwritten.
set -eu
APP=; BOTTLE=; NEWAPP=; NEWBOTTLE="Steam (Forza Horizon 5)"; DOAPP=1; DOBOTTLE=1
die() { echo "ERROR: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:?}"; shift 2;;
    --bottle) BOTTLE="${2:?}"; shift 2;;
    --new-app) NEWAPP="${2:?}"; shift 2;;
    --new-bottle) NEWBOTTLE="${2:?}"; shift 2;;
    --no-app-copy) DOAPP=0; shift;;
    --no-bottle-copy) DOBOTTLE=0; shift;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "unknown argument: $1";;
  esac
done
BOTTLES="${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}"
pgrep -x wineserver >/dev/null || pgrep -f 'wineserver-(x86|arm64)' >/dev/null && die "quit CrossOver and all bottles first"

if [ "$DOAPP" = 1 ]; then
  [ -n "$APP" ] || die "--app is required (or --no-app-copy)"
  APP="${APP%/}"; test -d "$APP/Contents/SharedSupport/CrossOver" || die "not a CrossOver app: $APP"
  [ -n "$NEWAPP" ] || NEWAPP="${APP%.app} (FH5).app"
  test ! -e "$NEWAPP" || die "$NEWAPP already exists"
  echo "copying $APP -> $NEWAPP"
  ditto "$APP" "$NEWAPP"
fi

if [ "$DOBOTTLE" = 1 ]; then
  [ -n "$BOTTLE" ] || die "--bottle is required (or --no-bottle-copy)"
  test -f "$BOTTLES/$BOTTLE/cxbottle.conf" || die "no bottle '$BOTTLE'"
  test ! -e "$BOTTLES/$NEWBOTTLE" || die "bottle '$NEWBOTTLE' already exists"
  echo "copying bottle '$BOTTLE' -> '$NEWBOTTLE'"
  ditto "$BOTTLES/$BOTTLE" "$BOTTLES/$NEWBOTTLE"
  # a copied bottle must not share the original's BottleID
  NEW_ID="$(uuidgen)" perl -i -pe 's/^"BottleID" = ".*"/"BottleID" = "$ENV{NEW_ID}"/' "$BOTTLES/$NEWBOTTLE/cxbottle.conf"
  grep '^"BottleID"' "$BOTTLES/$NEWBOTTLE/cxbottle.conf"
fi
echo "ok. Next: sh setup.sh --app \"${NEWAPP:-<app copy>}\" --bottle \"$NEWBOTTLE\""
