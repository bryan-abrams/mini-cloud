# CLI cheatsheet

Quick reference for Vault, Nomad, and Consul when using the mini-cloud stack. All URLs assume hostfile and TLS are set up (e.g. `vault.bry.an`, `nomad.bry.an`, `consul.bry.an`). See [Setup](setup.md) and [Usage](usage.md) for full context.

---

## Vault CLI

**Address (required):**
```bash
export VAULT_ADDR="https://vault.bry.an"
```

**Login and status:**
```bash
vault login                    # interactive; use root or other token
vault status                   # sealed state, version
```

**First-time init and unseal:**
```bash
vault operator init            # once; save unseal keys and root token
vault operator unseal          # after each restart; run 3 times with 3 keys
```

**Read secrets / issue tokens:**
```bash
vault read consul/creds/admin              # Consul ACL token for UI/workers
vault read nomad/creds/job-submitter      # Nomad token for job submit
vault read -field=secret_id nomad/creds/job-submitter   # token value only
```

**KV (if you use a KV engine):**
```bash
vault kv get secret/myapp
vault kv put secret/myapp key=value
```

---

## Nomad CLI

**Address and token (required for API):**
```bash
export NOMAD_ADDR="https://nomad.bry.an"
export NOMAD_TOKEN="<token>"   # from vault read nomad/creds/job-submitter or acl bootstrap
```

**Jobs:**
```bash
nomad job run path/to/job.hcl
nomad job stop <job>
nomad job status <job>
nomad job plan path/to/job.hcl
```

**Allocations and logs:**
```bash
nomad status <job>                           # allocations and nodes
nomad allocation status <alloc-id>           # single allocation
nomad alloc logs <alloc-id>                  # stdout/stderr
nomad alloc logs -f <alloc-id> <task>        # follow
```

**Nodes:**
```bash
nomad node status
nomad node status -self                       # from a node
```

**ACL (management token only):**
```bash
nomad acl bootstrap
nomad acl policy apply -description "..." <policy-name> <file.hcl>
nomad acl token create -name "..." -policy <policy-name>
```

---

## Consul CLI

**Address and token (ACLs enabled in this stack):**
```bash
export CONSUL_HTTP_ADDR="https://consul.bry.an"
export CONSUL_HTTP_TOKEN="<token>"   # from vault read consul/creds/admin
```

**Catalog and health:**
```bash
consul catalog services
consul catalog nodes
consul catalog nodes -service=example-server
consul members                    # agent cluster members
```

**KV (if used):**
```bash
consul kv get key/path
consul kv put key/path value
consul kv delete key/path
```

---

## Consul HTTP API

Use when you need to call Consul from a script or another tool. Base URL via nginx: `https://consul.bry.an`. Send the ACL token in the `X-Consul-Token` header.

**Common endpoints:**

| Purpose | Method | Endpoint |
|--------|--------|----------|
| List services | GET | `/v1/catalog/services` |
| Service instances | GET | `/v1/health/service/<service-name>` |
| Node checks | GET | `/v1/health/checks/<service-name>` |
| Deregister check | PUT | `/v1/catalog/deregister` (body: `{"Node":"<id>","CheckID":"<id>"}`) |

**Examples:**
```bash
# List services (token from env)
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" "https://consul.bry.an/v1/catalog/services"

# Healthy instances of a service
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" "https://consul.bry.an/v1/health/service/example-server"

# Deregister a stale check (get Node from health/checks, then:)
curl -X PUT "https://consul.bry.an/v1/catalog/deregister" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"Node":"<NODE_ID>","CheckID":"<CHECK_ID>"}'
```

If you use the CLI from the host, set `CONSUL_HTTP_ADDR="https://consul.bry.an"` and `CONSUL_HTTP_TOKEN`; the CLI will use them for requests.
