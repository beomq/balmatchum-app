#!/usr/bin/env bash
set -euo pipefail
set +x

readonly max_version_code=2100000000

die() {
  printf 'Play upload: %s\n' "$*" >&2
  exit 1
}

action=${1:-}
case "$action" in
  prepare|upload) ;;
  *) die 'usage: upload_play.sh prepare|upload' ;;
esac

: "${PLAY_ACCESS_TOKEN:?Missing Play access token}"
: "${FLAVOR:?Missing flavor}"
: "${GITHUB_REF:?Missing GitHub ref}"
: "${ANDROID_PACKAGE_NAME:?Missing Android package name}"
: "${PLAY_TRACK:?Missing Play track}"
: "${RELEASE_STATUS:?Missing release status}"

case "$FLAVOR" in
  dev)
    expected_ref=refs/heads/develop
    expected_package=com.beomq.balmatchum.dev
    bundle=build/app/outputs/bundle/devRelease/app-dev-release.aab
    ;;
  prod)
    expected_ref=refs/heads/main
    expected_package=com.beomq.balmatchum
    bundle=build/app/outputs/bundle/prodRelease/app-prod-release.aab
    ;;
  *) die "unsupported flavor: $FLAVOR" ;;
esac

[[ "$GITHUB_REF" == "$expected_ref" ]] ||
  die "$FLAVOR uploads require $expected_ref"
[[ "$ANDROID_PACKAGE_NAME" == "$expected_package" ]] ||
  die "unexpected package for $FLAVOR"
[[ "$PLAY_TRACK" == internal ]] || die 'Play track must be internal'
[[ "$RELEASE_STATUS" == draft ]] || die 'release status must be draft'

base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$ANDROID_PACKAGE_NAME"
upload_base="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$ANDROID_PACKAGE_NAME"
auth="Authorization: Bearer $PLAY_ACCESS_TOKEN"
edit_id=

delete_edit() {
  local deleting=${edit_id:-}
  [[ -n "$deleting" ]] || return 0
  if curl --fail-with-body --silent --show-error --max-time 60 \
    -X DELETE -H "$auth" "$base/edits/$deleting" >/dev/null; then
    edit_id=
  else
    printf 'Play upload: failed to delete edit %s\n' "$deleting" >&2
    return 1
  fi
}

cleanup_edit() {
  local status=$?
  if [[ -n "${edit_id:-}" ]]; then
    delete_edit || true
  fi
  return "$status"
}

create_edit() {
  local response
  response=$(curl --fail-with-body --silent --show-error --max-time 60 \
    -X POST -H "$auth" -H 'Content-Type: application/json' \
    -d '{}' "$base/edits")
  edit_id=$(jq -er '.id | select(type == "string" and length > 0)' <<< "$response")
  trap cleanup_edit EXIT
}

read_max_version_code() {
  local bundles apks tracks
  bundles=$(curl --fail-with-body --silent --show-error --max-time 60 \
    -H "$auth" "$base/edits/$edit_id/bundles")
  apks=$(curl --fail-with-body --silent --show-error --max-time 60 \
    -H "$auth" "$base/edits/$edit_id/apks")
  tracks=$(curl --fail-with-body --silent --show-error --max-time 60 \
    -H "$auth" "$base/edits/$edit_id/tracks")

  jq -en \
    --argjson bundles "$bundles" \
    --argjson apks "$apks" \
    --argjson tracks "$tracks" '
      [
        $bundles.bundles[]?.versionCode,
        $apks.apks[]?.versionCode,
        $tracks.tracks[]?.releases[]?.versionCodes[]?
      ]
      | map(
          if type == "number" then .
          elif type == "string" and test("^[0-9]+$") then tonumber
          else error("invalid versionCode in Play response")
          end
        )
      | if any(.[]; . < 0 or . != floor) then
          error("invalid versionCode in Play response")
        else
          max // 0
        end
    '
}

validate_version_code() {
  local value=$1
  [[ "$value" =~ ^[1-9][0-9]{0,9}$ ]] ||
    die 'VERSION_CODE must be a positive decimal integer'
  (( value < max_version_code )) ||
    die "VERSION_CODE must be below $max_version_code"
}

if [[ "$action" == prepare ]]; then
  : "${GITHUB_ENV:?Missing GITHUB_ENV}"
  manual=${VERSION_CODE:-}
  if [[ -n "$manual" ]]; then
    validate_version_code "$manual"
  fi

  create_edit
  current_max=$(read_max_version_code)
  delete_edit
  trap - EXIT

  (( current_max < max_version_code - 1 )) ||
    die "Play versionCode range is exhausted at $current_max"
  if [[ -n "$manual" ]]; then
    (( manual > current_max )) ||
      die "manual VERSION_CODE $manual must exceed Play maximum $current_max"
    selected=$manual
  else
    selected=$((current_max + 1))
  fi
  validate_version_code "$selected"
  printf 'VERSION_CODE=%s\n' "$selected" >> "$GITHUB_ENV"
  printf 'Selected %s versionCode %s (Play maximum %s).\n' \
    "$FLAVOR" "$selected" "$current_max"
  exit 0
fi

: "${VERSION_CODE:?Missing VERSION_CODE}"
validate_version_code "$VERSION_CODE"
[[ -s "$bundle" ]] || die "missing bundle: $bundle"

create_edit
current_max=$(read_max_version_code)
(( VERSION_CODE > current_max )) ||
  die "VERSION_CODE $VERSION_CODE is no longer above Play maximum $current_max"

# Do not retry this write automatically: a lost response does not prove failure.
if ! upload=$(curl --fail-with-body --silent --show-error --max-time 300 \
  -H "$auth" -H 'Content-Type: application/octet-stream' \
  --data-binary "@$bundle" \
  "$upload_base/edits/$edit_id/bundles?uploadType=media"); then
  jq -r '.error | {code, status, message}' <<< "$upload" >&2
  die 'bundle upload failed; edit will be discarded'
fi
jq -e --argjson expected "$VERSION_CODE" \
  '.versionCode == $expected' <<< "$upload" >/dev/null

release=$(jq -n --arg track "$PLAY_TRACK" --arg code "$VERSION_CODE" '
  {
    track: $track,
    releases: [{versionCodes: [$code], status: "draft"}]
  }
')
printf 'Updating internal draft track.\n'
curl --fail-with-body --silent --show-error --max-time 60 \
  -X PUT -H "$auth" -H 'Content-Type: application/json' \
  -d "$release" "$base/edits/$edit_id/tracks/$PLAY_TRACK"
printf '\nValidating edit.\n'
curl --fail-with-body --silent --show-error --max-time 60 \
  -X POST -H "$auth" "$base/edits/$edit_id:validate"
printf '\nCommitting draft without review.\n'
curl --fail-with-body --silent --show-error --max-time 60 \
  -X POST -H "$auth" \
  "$base/edits/$edit_id:commit?changesNotSentForReview=true&changesInReviewBehavior=ERROR_IF_IN_REVIEW"
edit_id=
trap - EXIT
printf 'Committed %s versionCode %s to internal (draft).\n' \
  "$FLAVOR" "$VERSION_CODE"
