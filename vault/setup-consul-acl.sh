#!/bin/sh
# Configure Vault to manage Consul ACLs. Run once after Vault is unsealed.
# Usage: docker exec -e VAULT_TOKEN=<root-token> vault sh /vault/scripts/setup-consul-acl.sh
set -e

if [ -z "$VAULT_TOKEN" ]; then
  echo "VAULT_TOKEN is required (use root token after unseal)"
  exit 1
fi

export VAULT_ADDR="http://127.0.0.1:8200"

# Enable Consul secrets engine (idempotent)
vault secrets enable -path=consul consul 2>/dev/null || true

# Configure Vault to talk to Consul; omit token so Vault bootstraps Consul ACLs
# (only works when Consul ACLs are enabled but not yet bootstrapped).
# If Consul was already bootstrapped, use: vault write consul/config/access address="consul:8500" scheme="http" token="<management-token>"
vault write consul/config/access address="consul:8500" scheme="http"

# Role for Consul UI / admin: tokens with global-management policy
vault write consul/roles/admin consul_policies="global-management"

echo "Consul ACL integration complete."
echo "Get a token for the Consul UI: vault read consul/creds/admin"
echo "Use the 'token' value in the Consul UI at https://consul.bry.an"
