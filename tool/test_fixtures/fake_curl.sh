#!/usr/bin/env bash
set -euo pipefail

: "${FAKE_CURL_LOG:?Missing fake curl log}"
: "${FAKE_CURL_STATE:?Missing fake curl state}"
: "${FAKE_BUNDLES_SEQUENCE:?Missing bundles sequence}"
: "${FAKE_APKS_SEQUENCE:?Missing APK sequence}"
: "${FAKE_TRACKS_SEQUENCE:?Missing tracks sequence}"

method=
data=
data_binary=
url=
while (($#)); do
  case "$1" in
    -X)
      method=$2
      shift 2
      ;;
    -H|-d|--data)
      if [[ "$1" == -d || "$1" == --data ]]; then
        data=$2
      fi
      shift 2
      ;;
    --data-binary)
      data_binary=$2
      shift 2
      ;;
    --max-time)
      shift 2
      ;;
    --fail-with-body|--silent|--show-error)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

if [[ -z "$method" ]]; then
  if [[ -n "$data" || -n "$data_binary" ]]; then
    method=POST
  else
    method=GET
  fi
fi

jq -cn \
  --arg method "$method" \
  --arg url "$url" \
  --arg data "$data" \
  --arg data_binary "$data_binary" \
  '{method: $method, url: $url, data: $data, dataBinary: $data_binary}' \
  >> "$FAKE_CURL_LOG"

next_edit() {
  local count=0
  if [[ -f "$FAKE_CURL_STATE/edit-count" ]]; then
    read -r count < "$FAKE_CURL_STATE/edit-count"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$FAKE_CURL_STATE/edit-count"
  printf '{"id":"edit-%s"}\n' "$count"
}

edit_index() {
  local id=${url#*/edits/edit-}
  id=${id%%/*}
  id=${id%%:*}
  printf '%s\n' "$((id - 1))"
}

sequence_item() {
  local sequence=$1
  local index
  index=$(edit_index)
  jq -cer --argjson index "$index" \
    '.[$index] // .[-1]' <<< "$sequence"
}

case "$method $url" in
  "POST "*"/edits")
    next_edit
    ;;
  "POST https://androidpublisher.googleapis.com/upload/"*"/bundles?uploadType=media")
    printf '{"versionCode":%s}\n' "${FAKE_UPLOAD_VERSION_CODE:?Missing fake upload version}"
    ;;
  "GET "*"/bundles")
    sequence_item "$FAKE_BUNDLES_SEQUENCE"
    ;;
  "GET "*"/apks")
    sequence_item "$FAKE_APKS_SEQUENCE"
    ;;
  "GET "*"/tracks")
    sequence_item "$FAKE_TRACKS_SEQUENCE"
    ;;
  "DELETE "*|"PUT "*|"POST "*":validate"|"POST "*":commit?"*)
    printf '{}\n'
    ;;
  *)
    printf 'Unexpected fake curl request: %s %s\n' "$method" "$url" >&2
    exit 64
    ;;
esac
