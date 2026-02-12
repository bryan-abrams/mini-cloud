#!/bin/sh
set -e
# Ensure data dir is writable by vault user (volume is often root-owned on first use)
chown -R vault:vault /vault/data 2>/dev/null || true
exec /usr/local/bin/docker-entrypoint.sh "$@"
