#!/bin/bash
# Point the bench at the database and Redis services in docker-compose.yml.
# Every host name below is a Compose service name, resolved on the Compose
# network, so none of it is environment-specific.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_bench
cd "$BENCH_DIR"

log_info "Configuring the bench"
bench set-config -g db_type mariadb
bench set-config -g db_host "$DB_HOST"
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379
# redis_socketio is kept for backward compatibility with older apps.
bench set-config -g redis_socketio redis://redis-queue:6379

log_info "========================================="
cat sites/common_site_config.json
log_info "========================================="
