#!/usr/bin/env bash
# Single source of release values: native schemes are derived from this JSON.
set -euo pipefail
set +x

die() {
  printf 'Release app config: %s\n' "$*" >&2
  exit 1
}

platform=${1:-}
out=${2:-}
case "$platform" in
  ios|android) ;;
  *) die 'usage: release_app_config.sh ios|android OUTPUT_JSON' ;;
esac
[[ -n "$out" ]] || die 'usage: release_app_config.sh ios|android OUTPUT_JSON'

readonly google_client='^([0-9]+)-[a-z0-9]+\.apps\.googleusercontent\.com$'

require() {
  local name=$1 pattern=$2 expected=$3
  local value=${!name:-}
  [[ -n "$value" ]] || die "$name is required ($expected)"
  [[ "$value" =~ $pattern ]] || die "$name is malformed (expected $expected)"
}

require SERVER_URL '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~-]+)*/$' \
  'https URL ending with /'
require KAKAO_NATIVE_APP_KEY '^[0-9a-f]{32}$' '32 lowercase hex characters'
require GOOGLE_SERVER_CLIENT_ID "$google_client" \
  '<project number>-<id>.apps.googleusercontent.com web client'

if [[ "$platform" == ios ]]; then
  require GOOGLE_IOS_CLIENT_ID "$google_client" \
    '<project number>-<id>.apps.googleusercontent.com iOS client'
  [[ "$GOOGLE_IOS_CLIENT_ID" != "$GOOGLE_SERVER_CLIENT_ID" ]] ||
    die 'GOOGLE_IOS_CLIENT_ID must be the iOS client, not the web client'
  # Cross-client ID tokens are issued only within one Google Cloud project.
  [[ "${GOOGLE_IOS_CLIENT_ID%%-*}" == "${GOOGLE_SERVER_CLIENT_ID%%-*}" ]] ||
    die 'GOOGLE_IOS_CLIENT_ID must belong to the GOOGLE_SERVER_CLIENT_ID project'
fi

mkdir -p "$(dirname "$out")"
if [[ "$platform" == ios ]]; then
  jq -n '{
    SERVER_URL: env.SERVER_URL,
    KAKAO_NATIVE_APP_KEY: env.KAKAO_NATIVE_APP_KEY,
    GOOGLE_SERVER_CLIENT_ID: env.GOOGLE_SERVER_CLIENT_ID,
    GOOGLE_CLIENT_ID: env.GOOGLE_IOS_CLIENT_ID,
    APPLE_SIGN_IN_ENABLED: "true"
  }' > "$out"
else
  # Apple stays hidden on Android: no Services ID web flow is configured.
  jq -n '{
    SERVER_URL: env.SERVER_URL,
    KAKAO_NATIVE_APP_KEY: env.KAKAO_NATIVE_APP_KEY,
    GOOGLE_SERVER_CLIENT_ID: env.GOOGLE_SERVER_CLIENT_ID
  }' > "$out"
fi
printf 'Release app config (%s) written: %s\n' "$platform" "$out"
