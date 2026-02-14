# Troubleshooting: issues arising from Consul ACLs

This stack runs Consul with ACLs enabled (default policy deny). Tokens are issued via Vault (`vault read consul/creds/admin`). When something talks to Consul without a valid token—or without sending the token for certain operations—Consul logs ACL blocks. This document sums up how to recognize those issues and track down the source.

---

## Symptom: "blocked by ACLs" with anonymous token

Consul logs show repeated lines like:

```
[WARN] agent: Check deregistration blocked by ACLs: check=_nomad-check-... accessorID="anonymous token"
[WARN] agent: Coordinate update blocked by ACLs: accessorID="anonymous token"
```

Or service deregistration blocked with `accessorID="anonymous token"`. That means Consul received a request that either had **no token** or a token it treated as unauthenticated, and the operation was denied.

**Why it's hard to deduce the source:** The log line does not say which host or process sent the request. You only see that the request was anonymous. So you have to correlate by behavior (e.g. who is running when the messages appear).

---

## Identifying who is sending the requests

- **Correlate with what's running.** For example: when the **Nomad workers** (external VMs running Nomad clients) are **stopped**, the deregistration and coordinate-update warnings **stop**. When the workers are **running**, the warnings **recur**. That strongly indicates the requests are coming from the **Nomad clients on the workers**, not from the Nomad server in Docker or from other services in the stack.

- **Enable Consul debug (or trace) logging** to get more detail around the time of the block. In `consul/config.hcl` add:
  ```hcl
  log_level = "DEBUG"
  ```
  Restart Consul (`docker restart consul`). Inspect logs when the warnings occur; some builds may include connection or request context. For maximum verbosity use `log_level = "TRACE"` (noisier). See [Enabling Consul debug logging](#enabling-consul-debug-logging) below.

- **Network visibility:** If you need to confirm by client IP, use `tcpdump` or similar on the Consul host (or the proxy in front of it) and correlate timestamps with the "blocked by ACLs" lines to see which source IPs are hitting Consul when those messages appear.

---

## Root cause (workers sending anonymous requests)

Once you've determined the source (e.g. Nomad clients on workers):

- The **token in the Nomad client config** on the workers may be correct (same token that works when you call Consul with it from the host).
- Nevertheless, for **some** Consul API calls—notably **service/check deregistration** and **coordinate updates**—the Nomad client can send requests **without** the token (or in a way Consul treats as anonymous). So Consul blocks those operations and logs "anonymous token".

So the issue is: the client has the token in config but does **not** use it for every Consul operation.

---

## What to verify on the workers

1. **Config file** — On each worker, open the Nomad client config (e.g. `/etc/nomad.d/client.hcl`) and confirm the `consul { }` block has `token = "<your-token>"` set and not empty. If the token is injected via env (e.g. `env("CONSUL_TOKEN")`), ensure that env var is set for the Nomad process (e.g. in the systemd unit).

2. **Environment variable** — Some code paths use `CONSUL_HTTP_TOKEN` from the process environment. Set it for the Nomad client on each worker (e.g. in the systemd unit):
   ```ini
   [Service]
   Environment="CONSUL_HTTP_TOKEN=<same-token-as-in-client.hcl>"
   ```
   Then `systemctl daemon-reload` and `systemctl restart nomad`. If the warnings stop, Nomad was not sending the config token for those operations.

3. **Token validity** — Ensure the token is not expired. Get a fresh token from Vault (`vault read consul/creds/admin`) and update both the Nomad server (Compose) and every worker, then restart the services that use it. See **usage.md** § "When a token expires".

---

## Fixes and workarounds

- **Set `CONSUL_HTTP_TOKEN` on workers** — As above. This often resolves the anonymous deregister/coordinate warnings if the config token is not being used for those calls.

- **Consul default token (workaround)** — In Consul's config, set the ACL **default token** to the same token you use for Nomad. Requests that arrive with no token will then be treated as that token, so the blocks (and log noise) stop. The underlying cause—Nomad not sending the token for some operations—remains; the default token only masks it. Use only if you understand the security implications (any unauthenticated request from a reachable client will use that token).

- **Nomad/Consul versions** — Check release notes and issues for your Nomad and Consul versions (e.g. "consul token", "deregister", "coordinate", "anonymous") in case a fix or known limitation is documented.

---

## Enabling Consul debug logging

To get more detail about requests and ACL blocks:

1. **Config file** — In `consul/config.hcl` add:
   ```hcl
   log_level = "DEBUG"
   ```
   For maximum verbosity:
   ```hcl
   log_level = "TRACE"
   ```

2. **Restart Consul:** `docker restart consul`

3. **Watch logs:** `docker logs -f consul`

Standard Consul logging may not include client IP on every request; DEBUG/TRACE can still give more context around the moment of the block. To definitively see "who" (client IP), combine with network capture (e.g. `tcpdump`) or audit logging if your Consul version supports it.

---

## Related ACL-related issues

- **Stale Consul entries** — After standby, restarts, or job purges, old Nomad allocations can leave service/check entries in Consul. Those can show as unhealthy or duplicate checks. Remove them via the catalog deregister API (see **usage.md** § "Removing a stale Consul check"). Ensure Nomad server and jobs use `checks_use_advertise = true` and `address_mode = "host"` where appropriate so checks target reachable addresses.

- **Token expiry** — Consul tokens from Vault have a TTL. When they expire, registration and health checks can fail or be denied. Update the token in Compose (e.g. `CONSUL_HTTP_TOKEN`), in the Nomad server env, and on every worker; then restart the services. See **usage.md** § "When a token expires".

- **Compose and Nomad server** — This stack supplies the Consul token to the Nomad server and consul-template via `CONSUL_HTTP_TOKEN` (or the equivalent env used by each). If you change the token, update that env and restart those containers so they use the new token.
