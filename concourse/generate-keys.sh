#!/bin/sh
set -e
WEB=concourse/keys/web
WRK=concourse/keys/worker
mkdir -p "$WEB" "$WRK"

echo "Generating Concourse keys (using concourse image)..."
docker run --rm -v "$(pwd)/$WEB:/keys" concourse/concourse:latest generate-key -t rsa -f /keys/session_signing_key
docker run --rm -v "$(pwd)/$WEB:/keys" concourse/concourse:latest generate-key -t ssh -f /keys/tsa_host_key
docker run --rm -v "$(pwd)/$WRK:/keys" concourse/concourse:latest generate-key -t ssh -f /keys/worker_key

cp "$WRK/worker_key.pub" "$WEB/authorized_worker_keys"
echo "Keys written to concourse/keys/web and concourse/keys/worker"
