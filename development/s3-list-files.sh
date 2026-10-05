#!/bin/bash
# List the objects in one bucket, or in every bucket when given none.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: s3-list-files.sh [BUCKET]

List the objects in BUCKET, or in every bucket when no name is given.
EOF
}

case "${1:-}" in
-h | --help)
    usage
    exit 0
    ;;
esac

require_secret S3_ACCESS_KEY
require_secret S3_SECRET_KEY

BUCKET="${1:-}"
CREDS="$S3_ACCESS_KEY:$S3_SECRET_KEY"

list_bucket() {
    local bucket="$1" response keys count
    log_info "Bucket: $bucket"
    response="$(curl -fsS "$S3_HOST/$bucket" --aws-sigv4 "$S3_SIGV4" --user "$CREDS" || true)"
    keys="$(echo "$response" | grep -oP '<Key>\K[^<]+' || true)"
    if [[ -n $keys ]]; then
        echo "$keys" | sed 's/^/  /'
        count="$(echo "$keys" | wc -l)"
        log_info "  Total: $count file(s)"
    else
        echo "  (empty)"
    fi
    echo
}

if [[ -n $BUCKET ]]; then
    list_bucket "$BUCKET"
    exit 0
fi

buckets="$(curl -fsS "$S3_HOST" --aws-sigv4 "$S3_SIGV4" --user "$CREDS" |
    grep -oP '<Name>\K[^<]+' || true)"
if [[ -z $buckets ]]; then
    log_warn "No buckets. Create one with s3-create-buckets.sh."
    exit 0
fi

for b in $buckets; do list_bucket "$b"; done
