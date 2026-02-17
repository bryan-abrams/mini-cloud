#!/bin/sh
# Configure Vault to issue Nomad ACL tokens. Run once after Nomad ACL is bootstrapped.
# Usage:
#   docker exec -e VAULT_TOKEN=<vault-root> -e NOMAD_TOKEN=<nomad-management-token> vault sh /vault/scripts/setup-nomad-secrets.sh
# Create the Nomad policy (e.g. job-submitter) in Nomad first, then pass its name as NOMAD_POLICY.
set -e

if [ -z "$VAULT_TOKEN" ]; then
  echo "VAULT_TOKEN is required (Vault root or admin token)"
  exit 1
fi
if [ -z "$NOMAD_TOKEN" ]; then
  echo "NOMAD_TOKEN is required (Nomad management token or token with acl token write)"
  exit 1
fi

export VAULT_ADDR="http://127.0.0.1:8200"

# Nomad API reachable from Vault container on the same Docker network
NOMAD_ADDR="${NOMAD_ADDR:-http://nomad-server:4646}"

# Enable Nomad secrets engine (idempotent)
vault secrets enable -path=nomad nomad 2>/dev/null || true

# Configure Vault to talk to Nomad and create tokens
vault write nomad/config/access \
  address="$NOMAD_ADDR" \
  token="$NOMAD_TOKEN"

# Role that grants a Nomad ACL policy (create the policy in Nomad first, e.g. nomad acl policy apply ...)
NOMAD_POLICY="${NOMAD_POLICY:-job-submitter}"
NOMAD_ROLE="${NOMAD_ROLE:-$NOMAD_POLICY}"
vault write nomad/role/"$NOMAD_ROLE" policies="$NOMAD_POLICY"

echo "Nomad secrets engine configured."
echo "Get a Nomad token: vault read nomad/creds/$NOMAD_ROLE"
echo "Use the 'secret_id' as NOMAD_TOKEN when running nomad job run ..."
