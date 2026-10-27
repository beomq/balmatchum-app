#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

for scenario in missing wrong correct; do
  # Given
  activity=
  if [[ "$scenario" != missing ]]; then
    scheme=wrong
    if [[ "$scenario" == correct ]]; then
      scheme=kakao0123456789abcdef0123456789abcdef
    fi
    activity="<activity android:name=\"com.kakao.sdk.flutter.auth.AuthCodeHandlerActivity\">
      <intent-filter><data android:host=\"oauth\" android:scheme=\"$scheme\"/></intent-filter>
    </activity>"
  fi
  printf '%s\n' "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\"
    package=\"com.beomq.balmatchum\" android:versionCode=\"1\" android:versionName=\"1.0\">
    <application>
      <meta-data android:name=\"com.google.android.gms.ads.APPLICATION_ID\"
        android:value=\"ca-app-pub-1234567890123456~1234567890\"/>
      $activity
    </application></manifest>" > "$test_root/manifest.xml"

  # When
  status=0
  bash "$tool_dir/verify_android_bundle.sh" manifest prod "$test_root/manifest.xml" \
    > "$test_root/output" 2>&1 || status=$?

  # Then
  if [[ "$scenario" == correct ]]; then
    [[ "$status" == 0 ]] || { printf 'correct manifest rejected\n' >&2; exit 1; }
    if grep -Fq "$scheme" "$test_root/output"; then
      printf 'Kakao key leaked in verifier output\n' >&2
      exit 1
    fi
  else
    [[ "$status" != 0 ]] || { printf '%s Kakao configuration accepted\n' "$scenario" >&2; exit 1; }
  fi
  printf 'ok - prod Kakao manifest %s\n' "$scenario"
done
