#!/usr/bin/env bash
# Publishes Unpaged to Google Play through the Android Publisher API.
#
#   play/publish.sh listing                 # text from listings/, images from $PLAY_ASSETS
#   play/publish.sh bundle <track> [status] # upload the release AAB to internal|alpha|beta|production
#
# Auth: your gcloud login impersonates the publisher service account, so no key file exists.
# One-time setup is android/play/setup-wizard.sh. Override with PLAY_SERVICE_ACCOUNT.
# Images: PLAY_ASSETS holds icon.png, featureGraphic.png and phoneScreenshots/*.png.
# A new app accepts only status=draft until its first release is rolled out in Play Console.
set -euo pipefail

PACKAGE=app.unpaged
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${PLAY_GCP_PROJECT:-$(cat "$HOME/.config/unpaged/play-gcp-project" 2>/dev/null || true)}"
SA="${PLAY_SERVICE_ACCOUNT:-unpaged-play-publisher@${PROJECT}.iam.gserviceaccount.com}"
ASSETS="${PLAY_ASSETS:-$HOME/.config/unpaged/play-assets}"
API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PACKAGE"
UPLOAD="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PACKAGE"
LANG_CODE=en-US

[[ -n "$PROJECT" || -n "${PLAY_SERVICE_ACCOUNT:-}" ]] || { echo "Run play/setup-wizard.sh first (no GCP project recorded)." >&2; exit 1; }
TOKEN="$(gcloud auth print-access-token --impersonate-service-account="$SA" \
  --scopes=https://www.googleapis.com/auth/androidpublisher 2>/dev/null)" \
  || { echo "Could not get a token for $SA. Run 'gcloud auth login' and check the wizard's IAM stage." >&2; exit 1; }

call() { # method url [curl args...] -> body on stdout, fails loudly on HTTP errors
  local method=$1 url=$2; shift 2
  local out; out="$(mktemp)"
  local code; code="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $TOKEN" "$@" "$url")"
  if [[ "$code" != 2* ]]; then echo "$method $url -> HTTP $code" >&2; cat "$out" >&2; echo >&2; rm -f "$out"; return 1; fi
  cat "$out"; rm -f "$out"
}

EDIT="$(call POST "$API/edits" | jq -r .id)"
trap '[[ -n "${COMMITTED:-}" ]] || call DELETE "$API/edits/$EDIT" >/dev/null 2>&1 || true' EXIT
echo "Edit $EDIT opened"

listing() {
  local dir="$HERE/listings/$LANG_CODE"
  jq -n --arg t "$(cat "$dir/title.txt")" --arg s "$(cat "$dir/short_description.txt")" --arg f "$(cat "$dir/full_description.txt")" \
    '{language:"en-US", title:$t, shortDescription:$s, fullDescription:$f}' \
    | call PUT "$API/edits/$EDIT/listings/$LANG_CODE" -H 'Content-Type: application/json' --data-binary @- >/dev/null
  echo "Listing text updated"
  jq -n '{defaultLanguage:"en-US", contactEmail:"andrei.baluta@yahoo.com", contactWebsite:"https://unpaged.app/support/"}' \
    | call PATCH "$API/edits/$EDIT/details" -H 'Content-Type: application/json' --data-binary @- >/dev/null
  echo "Contact details updated"

  upload_image() { # type file
    call POST "$UPLOAD/edits/$EDIT/listings/$LANG_CODE/$1?uploadType=media" -H 'Content-Type: image/png' --data-binary "@$2" >/dev/null
    echo "  $1 <- $(basename "$2")"
  }
  for type in icon featureGraphic phoneScreenshots; do call DELETE "$API/edits/$EDIT/listings/$LANG_CODE/$type" >/dev/null; done
  upload_image icon "$ASSETS/icon.png"
  upload_image featureGraphic "$ASSETS/featureGraphic.png"
  local shot; for shot in "$ASSETS"/phoneScreenshots/*.png; do upload_image phoneScreenshots "$shot"; done
}

bundle() {
  local track=${1:?track: internal, alpha, beta or production} status=${2:-draft}
  local aab="$HERE/../app/build/outputs/bundle/release/app-release.aab"
  [[ -f "$aab" ]] || { echo "Build it first: ./gradlew :app:bundleRelease" >&2; exit 1; }
  local version; version="$(call POST "$UPLOAD/edits/$EDIT/bundles?uploadType=media" \
    -H 'Content-Type: application/octet-stream' --data-binary "@$aab" | jq -r .versionCode)"
  echo "Uploaded versionCode $version"
  jq -n --arg v "$version" --arg s "$status" --arg n "$(cat "$HERE/release-notes/$LANG_CODE/default.txt")" \
    '{releases:[{versionCodes:[$v], status:$s, releaseNotes:[{language:"en-US", text:$n}]}]}' \
    | call PUT "$API/edits/$EDIT/tracks/$track" -H 'Content-Type: application/json' --data-binary @- >/dev/null
  echo "Track $track: versionCode $version ($status)"
}

case "${1:-}" in
  listing) listing ;;
  bundle) shift; bundle "$@" ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
call POST "$API/edits/$EDIT:commit" >/dev/null && COMMITTED=1
echo "Edit committed"
