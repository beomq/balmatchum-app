#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
sut="$tool_dir/upload_play.sh"
fixture="$tool_dir/test_fixtures/fake_curl.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
install -m 0755 "$fixture" "$test_root/curl"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_env_version() {
  local expected=$1
  [[ "$(tail -n 1 "$github_env")" == "VERSION_CODE=$expected" ]] ||
    fail "expected VERSION_CODE=$expected"
}

assert_request() {
  local filter=$1
  jq -s -e "any(.[]; $filter)" "$curl_log" >/dev/null ||
    fail "missing request matching: $filter"
}

assert_no_request() {
  local filter=$1
  if jq -s -e "any(.[]; $filter)" "$curl_log" >/dev/null 2>&1; then
    fail "unexpected request matching: $filter"
  fi
}

new_case() {
  case_dir="$test_root/case"
  rm -rf "$case_dir"
  mkdir -p "$case_dir/state"
  curl_log="$case_dir/curl.ndjson"
  github_env="$case_dir/github-env"
  : > "$curl_log"
  : > "$github_env"
  base_env=(
    "PATH=$test_root:$PATH"
    "PLAY_ACCESS_TOKEN=fake-token"
    "FLAVOR=dev"
    "GITHUB_REF=refs/heads/develop"
    "ANDROID_PACKAGE_NAME=com.beomq.balmatchum.dev"
    "PLAY_TRACK=internal"
    "RELEASE_STATUS=draft"
    "GITHUB_ENV=$github_env"
    "FAKE_CURL_LOG=$curl_log"
    "FAKE_CURL_STATE=$case_dir/state"
    'FAKE_BUNDLES_SEQUENCE=[{"bundles":[]}]'
    'FAKE_APKS_SEQUENCE=[{"apks":[]}]'
    'FAKE_TRACKS_SEQUENCE=[{"tracks":[]}]'
    "FAKE_UPLOAD_VERSION_CODE=1"
  )
}

run_sut() {
  local action=$1
  shift
  (
    cd "$case_dir"
    env "${base_env[@]}" "$@" bash "$sut" "$action"
  )
}

new_case
run_sut prepare \
  'FAKE_BUNDLES_SEQUENCE=[{"bundles":[{"versionCode":4}]}]' \
  'FAKE_APKS_SEQUENCE=[{"apks":[{"versionCode":7}]}]' \
  'FAKE_TRACKS_SEQUENCE=[{"tracks":[{"releases":[{"versionCodes":["11"]}]}]}]' \
  VERSION_CODE= >/dev/null
assert_env_version 12
assert_request '.method == "POST" and (.url | endswith("/com.beomq.balmatchum.dev/edits"))'
assert_request '.method == "DELETE" and (.url | endswith("/edits/edit-1"))'

new_case
run_sut prepare \
  FLAVOR=prod \
  GITHUB_REF=refs/heads/main \
  ANDROID_PACKAGE_NAME=com.beomq.balmatchum \
  'FAKE_BUNDLES_SEQUENCE=[{"bundles":[{"versionCode":20}]}]' \
  VERSION_CODE= >/dev/null
assert_env_version 21
assert_request '.url | contains("/applications/com.beomq.balmatchum/")'
printf 'ok - dev and prod mappings use exact refs and packages\n'

for invalid in \
  'FLAVOR=qa' \
  'GITHUB_REF=refs/heads/main' \
  'ANDROID_PACKAGE_NAME=com.example.invalid' \
  'PLAY_TRACK=beta' \
  'RELEASE_STATUS=completed'
do
  new_case
  if run_sut prepare "$invalid" VERSION_CODE= >/dev/null 2>&1; then
    fail "accepted invalid input: $invalid"
  fi
  [[ ! -s "$curl_log" ]] || fail "requested Play for invalid input: $invalid"
done
printf 'ok - invalid flavor, ref, package, track, and status fail before requests\n'

new_case
run_sut prepare \
  'FAKE_BUNDLES_SEQUENCE=[{"bundles":[{"versionCode":5}]}]' \
  'FAKE_APKS_SEQUENCE=[{"apks":[{"versionCode":9}]}]' \
  'FAKE_TRACKS_SEQUENCE=[{"tracks":[{"releases":[{"versionCodes":["13"]}]}]}]' \
  VERSION_CODE=100 >/dev/null
assert_env_version 100
printf 'ok - maximum includes bundles, APKs, tracks, and higher manual code\n'

new_case
advanced_bundles='[
  {"bundles":[{"versionCode":10}]},
  {"bundles":[{"versionCode":20}]}
]'
run_sut prepare "FAKE_BUNDLES_SEQUENCE=$advanced_bundles" VERSION_CODE= >/dev/null
assert_env_version 11
run_sut prepare "FAKE_BUNDLES_SEQUENCE=$advanced_bundles" VERSION_CODE= >/dev/null
assert_env_version 21
printf 'ok - rerun observes an advanced Play maximum\n'

new_case
if run_sut prepare VERSION_CODE=2100000000 >/dev/null 2>&1; then
  fail 'accepted out-of-range manual version'
fi
[[ ! -s "$curl_log" ]] || fail 'requested Play for out-of-range manual version'

new_case
if run_sut prepare \
  'FAKE_TRACKS_SEQUENCE=[{"tracks":[{"releases":[{"versionCodes":["2099999999"]}]}]}]' \
  VERSION_CODE= >/dev/null 2>&1; then
  fail 'accepted exhausted Play version range'
fi
assert_request '.method == "DELETE" and (.url | endswith("/edits/edit-1"))'
printf 'ok - range and exhaustion checks are strict\n'

new_case
race_bundles='[
  {"bundles":[{"versionCode":10}]},
  {"bundles":[{"versionCode":11}]}
]'
run_sut prepare "FAKE_BUNDLES_SEQUENCE=$race_bundles" VERSION_CODE= >/dev/null
assert_env_version 11
mkdir -p "$case_dir/build/app/outputs/bundle/devRelease"
printf 'fixture-aab\n' \
  > "$case_dir/build/app/outputs/bundle/devRelease/app-dev-release.aab"
if run_sut upload \
  "FAKE_BUNDLES_SEQUENCE=$race_bundles" \
  VERSION_CODE=11 >/dev/null 2>&1; then
  fail 'uploaded a version consumed after prepare'
fi
assert_no_request '.url | startswith("https://androidpublisher.googleapis.com/upload/")'
assert_request '.method == "DELETE" and (.url | endswith("/edits/edit-2"))'
printf 'ok - concurrent version consumption fails before binary upload\n'

new_case
mkdir -p "$case_dir/build/app/outputs/bundle/prodRelease"
printf 'fixture-aab\n' \
  > "$case_dir/build/app/outputs/bundle/prodRelease/app-prod-release.aab"
run_sut upload \
  FLAVOR=prod \
  GITHUB_REF=refs/heads/main \
  ANDROID_PACKAGE_NAME=com.beomq.balmatchum \
  'FAKE_BUNDLES_SEQUENCE=[{"bundles":[{"versionCode":10}]}]' \
  FAKE_UPLOAD_VERSION_CODE=12 \
  VERSION_CODE=12 >/dev/null
assert_request '
  .method == "PUT"
  and (.url | endswith("/tracks/internal"))
  and (.data | fromjson | .releases[0].status == "draft")
'
assert_request '
  .method == "POST"
  and (.url | endswith(":commit?changesNotSentForReview=true&changesInReviewBehavior=ERROR_IF_IN_REVIEW"))
'
assert_no_request '.method == "DELETE"'
printf 'ok - upload uses literal draft and no-review commit controls\n'

new_case
mkdir -p "$case_dir/build/app/outputs/bundle/devRelease"
printf 'fixture-aab\n' \
  > "$case_dir/build/app/outputs/bundle/devRelease/app-dev-release.aab"
if run_sut upload \
  FAKE_UPLOAD_VERSION_CODE=12 \
  VERSION_CODE=13 >/dev/null 2>&1; then
  fail 'accepted a mismatched upload response version'
fi
assert_no_request '.method == "PUT"'
assert_request '.method == "DELETE" and (.url | endswith("/edits/edit-1"))'
printf 'ok - upload response version is verified before track mutation\n'

printf 'All upload_play fixture tests passed.\n'
