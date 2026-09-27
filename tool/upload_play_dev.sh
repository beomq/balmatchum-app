#!/usr/bin/env bash
set -euo pipefail
set +x

: "${PLAY_ACCESS_TOKEN:?Missing Play access token}"
[[ "${ANDROID_PACKAGE_NAME:-}" == 'com.beomq.balmatchum.dev' ]]
[[ "${PLAY_TRACK:-}" == 'internal' ]]
[[ "${VERSION_CODE:-}" =~ ^[1-9][0-9]{0,9}$ ]]
(( VERSION_CODE > 1 && VERSION_CODE <= 2100000000 ))
[[ "${RELEASE_STATUS:-}" == 'draft' || "${RELEASE_STATUS:-}" == 'completed' ]]

bundle=build/app/outputs/bundle/devRelease/app-dev-release.aab
[[ -s "$bundle" ]]
base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$ANDROID_PACKAGE_NAME"
auth="Authorization: Bearer $PLAY_ACCESS_TOKEN"

edit=$(curl --fail-with-body --silent --show-error --max-time 60 \
  -H "$auth" -H 'Content-Type: application/json' -d '{}' "$base/edits")
edit_id=$(jq -er '.id | select(type == "string" and length > 0)' <<< "$edit")
printf 'Created Play edit: %s\n' "$edit_id"

# Do not retry writes automatically: a lost response does not prove upload failure.
upload=$(curl --fail-with-body --silent --show-error --max-time 300 \
  -H "$auth" -H 'Content-Type: application/octet-stream' \
  --data-binary "@$bundle" \
  "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$ANDROID_PACKAGE_NAME/edits/$edit_id/bundles?uploadType=media")
jq -e --argjson expected "$VERSION_CODE" '.versionCode == $expected' <<< "$upload"

release=$(jq -n --arg track "$PLAY_TRACK" --arg code "$VERSION_CODE" \
  --arg status "$RELEASE_STATUS" \
  '{track: $track, releases: [{versionCodes: [$code], status: $status}]}')
curl --fail-with-body --silent --show-error --max-time 60 \
  -X PUT -H "$auth" -H 'Content-Type: application/json' \
  -d "$release" "$base/edits/$edit_id/tracks/$PLAY_TRACK"
curl --fail-with-body --silent --show-error --max-time 60 \
  -X POST -H "$auth" "$base/edits/$edit_id:validate"
curl --fail-with-body --silent --show-error --max-time 60 \
  -X POST -H "$auth" \
  "$base/edits/$edit_id:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
printf '\nCommitted Dev versionCode %s to internal (%s).\n' "$VERSION_CODE" "$RELEASE_STATUS"
