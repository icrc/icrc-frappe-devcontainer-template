#!/bin/bash
# List the buckets in the local S3 service.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_secret S3_ACCESS_KEY
require_secret S3_SECRET_KEY

curl -fsS "$S3_HOST" \
    --aws-sigv4 "$S3_SIGV4" \
    --user "$S3_ACCESS_KEY:$S3_SECRET_KEY" |
    grep -oP '<Name>\K[^<]+' || log_warn "No buckets."
