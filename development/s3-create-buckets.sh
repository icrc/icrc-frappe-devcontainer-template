#!/bin/bash
# Create buckets in the local S3 service, for apps that keep files outside the
# database. Credentials come from .devcontainer/.env, the same ones the
# service itself was configured with.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: s3-create-buckets.sh [BUCKET ...]

Create one bucket per name against the seaweedfs service. Default:
frappe-files. Creating a bucket that exists is not an error.

From inside the container the endpoint is http://seaweedfs:8333, from the
host http://localhost:9100.
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

buckets=("$@")
[[ ${#buckets[@]} -gt 0 ]] || buckets=(frappe-files)

for bucket in "${buckets[@]}"; do
    log_info "Creating bucket $bucket"
    curl -fsS -X PUT "$S3_HOST/$bucket" \
        --aws-sigv4 "$S3_SIGV4" \
        --user "$S3_ACCESS_KEY:$S3_SECRET_KEY" ||
        log_warn "  $bucket: not created (it may already exist)"
done

log_info "Done."
