#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
cd "$root/android"

for port in 0 65536 99999 1 443 65535; do
  # Given
  defines=$(printf '%s\n' "SERVER_URL=https://example.test:$port/" \
    'KAKAO_NATIVE_APP_KEY=0123456789abcdef0123456789abcdef' \
    'GOOGLE_SERVER_CLIENT_ID=123456789012-test.apps.googleusercontent.com' |
    while IFS= read -r define; do printf '%s' "$define" | base64 | tr -d '\n'; printf ','; done)

  # When
  status=0
  ./gradlew :app:validateProdReleaseAppConfig "-Pdart-defines=${defines%,}" \
    > "$test_root/output" 2>&1 || status=$?

  # Then
  if (( port < 1 || port > 65535 )); then
    if [[ "$status" == 0 ]] || ! grep -Fq SERVER_URL "$test_root/output"; then
      printf 'Gradle accepted invalid port %s\n' "$port" >&2
      exit 1
    fi
  else
    [[ "$status" == 0 ]] || {
      printf 'Gradle rejected valid port %s\n' "$port" >&2; exit 1;
    }
  fi
  printf 'ok - Gradle URL port %s\n' "$port"
done
