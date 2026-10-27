#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
sut="$tool_dir/release_app_config.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

readonly server='https://balmatchum-prod.example.test/'
readonly kakao='0123456789abcdef0123456789abcdef'
readonly google_server='123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com'
readonly google_ios='123456789012-zyxwvutsrqponmlkjihgfedcba543210.apps.googleusercontent.com'

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

run_sut() {
  local platform=$1
  shift
  env -i PATH="$PATH" \
    SERVER_URL="$server" \
    KAKAO_NATIVE_APP_KEY="$kakao" \
    GOOGLE_SERVER_CLIENT_ID="$google_server" \
    GOOGLE_IOS_CLIENT_ID="$google_ios" \
    "$@" bash "$sut" "$platform" "$out"
}

expect_rejected() {
  local platform=$1 needle=$2
  shift 2
  out="$test_root/$platform-rejected/app-config.json"
  if run_sut "$platform" "$@" > /dev/null 2> "$test_root/stderr"; then
    fail "$platform accepted: $*"
  fi
  grep -Fq "$needle" "$test_root/stderr" ||
    fail "$platform error for '$*' does not name $needle: $(cat "$test_root/stderr")"
  [[ ! -e "$out" ]] || fail "$platform wrote config for rejected input: $*"
}

out="$test_root/android/app-config.json"
run_sut android
jq -e --arg server "$server" --arg kakao "$kakao" --arg google "$google_server" '
  . == {
    SERVER_URL: $server,
    KAKAO_NATIVE_APP_KEY: $kakao,
    GOOGLE_SERVER_CLIENT_ID: $google
  }
' "$out" > /dev/null || fail "unexpected Android config: $(cat "$out")"
printf 'ok - Android config carries server, Kakao and Google server client only\n'

out="$test_root/ios/app-config.json"
run_sut ios
jq -e --arg ios "$google_ios" '
  .GOOGLE_CLIENT_ID == $ios
  and .APPLE_SIGN_IN_ENABLED == "true"
  and (keys | length) == 5
' "$out" > /dev/null || fail "unexpected iOS config: $(cat "$out")"
printf 'ok - iOS config adds the iOS Google client and native Apple sign-in\n'

for name in SERVER_URL KAKAO_NATIVE_APP_KEY GOOGLE_SERVER_CLIENT_ID; do
  for platform in android ios; do
    expect_rejected "$platform" "$name" "$name="
  done
done
expect_rejected ios GOOGLE_IOS_CLIENT_ID GOOGLE_IOS_CLIENT_ID=
printf 'ok - every required value fails closed when missing\n'

expect_rejected android SERVER_URL SERVER_URL=http://balmatchum-prod.example.test/
expect_rejected android SERVER_URL SERVER_URL=https://balmatchum-prod.example.test
for platform in ios android; do
  for port in 0 65536 99999; do
    expect_rejected "$platform" SERVER_URL "SERVER_URL=https://example.test:$port/"
  done
  for port in 1 443 65535; do
    out="$test_root/$platform-port-$port/app-config.json"
    run_sut "$platform" "SERVER_URL=https://example.test:$port/" > /dev/null
    jq -e --arg url "https://example.test:$port/" '.SERVER_URL == $url' "$out" > /dev/null
  done
done
printf 'ok - URL port boundaries are enforced on both platforms\n'
expect_rejected android KAKAO_NATIVE_APP_KEY KAKAO_NATIVE_APP_KEY=0123456789ABCDEF0123456789ABCDEF
expect_rejected android KAKAO_NATIVE_APP_KEY KAKAO_NATIVE_APP_KEY=0123456789abcdef
expect_rejected android GOOGLE_SERVER_CLIENT_ID GOOGLE_SERVER_CLIENT_ID=not-a-client-id
expect_rejected ios GOOGLE_IOS_CLIENT_ID \
  GOOGLE_IOS_CLIENT_ID=999999999999-zyxwvutsrqponmlkjihgfedcba543210.apps.googleusercontent.com
expect_rejected ios GOOGLE_IOS_CLIENT_ID "GOOGLE_IOS_CLIENT_ID=$google_server"
printf 'ok - malformed URLs, keys and cross-project Google clients are rejected\n'

out="$test_root/invalid/app-config.json"
if run_sut web > /dev/null 2>&1; then
  fail 'accepted unsupported platform'
fi
printf 'ok - only ios and android are supported\n'

printf 'All release_app_config tests passed.\n'
