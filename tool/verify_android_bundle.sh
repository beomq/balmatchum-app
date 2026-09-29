#!/usr/bin/env bash
set -euo pipefail
set +x

if [[ "${1:-}" == preflight ]]; then
  [[ "${GITHUB_REF:-}" == refs/heads/chore/cicd-validation ]] || { echo 'Signing validation requires chore/cicd-validation' >&2; exit 1; }
  : "${KEYSTORE_BASE64:?Missing Prod keystore}"
  : "${ANDROID_STORE_PASSWORD:?Missing Prod store password}"
  : "${ANDROID_KEY_PASSWORD:?Missing Prod key password}"
  exit 0
fi

bundle=${1:?Usage: verify_prod_bundle.sh AAB}
: "${BUNDLETOOL_JAR:?Missing bundletool}"
: "${LLVM_READELF:?Missing llvm-readelf}"
: "${ZIPALIGN:?Missing zipalign}"
: "${APKSIGNER:?Missing apksigner}"
: "${ANDROID_STORE_FILE:?Missing Prod keystore path}"
: "${ANDROID_STORE_PASSWORD:?Missing Prod store password}"
: "${ANDROID_KEY_PASSWORD:?Missing Prod key password}"
case "${FLAVOR:?Missing flavor}" in
  prod) package=com.beomq.balmatchum; expected=5756f95ecb2910820ba1da7acbe32344a56730cb6bc2924e4f1aeb6b2bc5b6ee ;;
  dev) package=com.beomq.balmatchum.dev; expected=66a05b5d1602aa2680daa060364219c7b1a75468bad0ea3961fc3b969a7b94b7 ;;
  *) echo 'Unsupported flavor' >&2; exit 1 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

java -jar "$BUNDLETOOL_JAR" validate --bundle="$bundle"
java -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$bundle" --module=base > "$work/manifest.xml"
python3 - "$work/manifest.xml" "$package" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = '{http://schemas.android.com/apk/res/android}'
assert root.attrib['package'] == sys.argv[2], 'Unexpected package'
assert int(root.attrib[ns + 'versionCode']) > 0, 'Invalid versionCode'
assert root.attrib[ns + 'versionName'], 'Missing versionName'
print('Package/version:', root.attrib['package'], root.attrib[ns + 'versionName'], root.attrib[ns + 'versionCode'])
PY
jarsigner -verify "$bundle"
keytool -J-Duser.language=en -printcert -jarfile "$bundle" > "$work/certificate.txt"
fingerprint=$(awk '/SHA256:/ {print $2}' "$work/certificate.txt" | tr -d ':' | tr '[:upper:]' '[:lower:]')
[[ "$fingerprint" == "$expected" ]] || { echo 'Unexpected AAB signer' >&2; exit 1; }
java -jar "$BUNDLETOOL_JAR" dump config --bundle="$bundle" > "$work/config.json"
jq -e '.optimizations.uncompressNativeLibraries | .enabled == true and .alignment == "PAGE_ALIGNMENT_16K"' "$work/config.json"
unzip -q "$bundle" 'base/lib/*' -d "$work"
count=0
while IFS= read -r -d '' library; do
  "$LLVM_READELF" -lW "$library" > "$work/elf.txt"
  python3 - "$work/elf.txt" <<'PY'
import sys
rows = [line.split() for line in open(sys.argv[1]) if line.strip().startswith('LOAD ')]
assert rows, 'Missing LOAD segments'
assert all(int(row[-1], 16) >= 16384 for row in rows), 'ELF alignment below 16KB'
PY
  count=$((count + 1))
done < <(find "$work/base/lib" -name '*.so' -print0)
(( count > 0 ))
umask 077
printf '%s\n' "$ANDROID_STORE_PASSWORD" > "$work/store-password"
printf '%s\n' "$ANDROID_KEY_PASSWORD" > "$work/key-password"
java -jar "$BUNDLETOOL_JAR" build-apks --bundle="$bundle" --output="$work/prod.apks" --mode=universal \
  --ks="$ANDROID_STORE_FILE" --ks-key-alias="balmatchum-$FLAVOR-upload" \
  --ks-pass="file:$work/store-password" --key-pass="file:$work/key-password"
unzip -q "$work/prod.apks" universal.apk -d "$work"
"$ZIPALIGN" -c -P 16 4 "$work/universal.apk"
"$APKSIGNER" verify --print-certs "$work/universal.apk" > "$work/apk-certificate.txt"
grep -Fq "certificate SHA-256 digest: $expected" "$work/apk-certificate.txt"
shasum -a 256 "$bundle"
printf 'Verified signer %s; %s ELF libraries; 16KB ZIP alignment\n' "$expected" "$count"
