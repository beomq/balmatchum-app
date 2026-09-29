#!/usr/bin/env bash
set -euo pipefail
set +x

export FLAVOR=${FLAVOR:-dev}
exec bash "$(dirname "$0")/upload_play.sh" "${1:-upload}"
