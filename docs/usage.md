# Usage

Once the stack is up and you've completed setup (TLS certs, hostfile, unsealing Vault, Nomad ACL bootstrap, etc.; see **setup.md**), this is where to go and what URLs to use for each portal and service. All URLs use HTTPS. Ensure your hostfile resolves these hostnames to the host (e.g. `127.0.0.1`); see **setup.md** § 2.2.

---

## What to expect

After the stack is running and (if you use them) workers are set up, you should see:

- **Nomad** — Client nodes (instances) listed and ready, waiting for jobs. Submit a job and you'll see allocations placed on those nodes.
- **Consul** — The service catalog shows registered services, including Consul itself and the Nomad server. Nodes and health checks reflect the current state of the stack and any workers.
- **Vault** — Once you've run the Consul ACL setup script (see **setup.md** § 2.5), you'll see a secrets engine for Consul (e.g. `consul/`) that can issue tokens. After you bootstrap Nomad ACLs and run the Nomad secrets setup (see **setup.md** § 2.6), Vault can also issue Nomad tokens (e.g. `nomad/creds/job-submitter`). The Nomad server uses Consul for coordination and is registered there; Vault is the place you go to get Consul ACL tokens for the UI or for workers.

---

## Using the portals

### Vault — https://vault.bry.an

Web UI and API. Vault must be **unsealed** before the UI or API will work (see **setup.md** § 2.5). In the UI, use "Sign in" with a token (e.g. root token after `vault operator init`, or a token from another method). From the CLI: set `export VAULT_ADDR="https://vault.bry.an"`, then `vault login` and `vault read/write` as needed.

### Nomad — https://nomad.bry.an

Nomad UI and API for viewing jobs, allocations, and client nodes and for submitting jobs. ACLs are enabled; you must use a token to submit jobs. From the CLI: set `export NOMAD_ADDR="https://nomad.bry.an"` and `export NOMAD_TOKEN="<token>"` (get a token from Vault: `vault read nomad/creds/job-submitter` — see **setup.md** § 2.6). Ensure TLS is trusted (e.g. mkcert CA on the host), then `nomad job run`, `nomad status`, etc.

### Consul — https://consul.bry.an

Consul UI for the service catalog, nodes, health checks, and KV store. With ACLs enabled (as in this stack), click "Log in" and enter a Consul ACL token (e.g. from `vault read consul/creds/admin` after running the Consul ACL setup script; see **setup.md** § 2.5 and § 2.6).

### Concourse CI — https://ci.bry.an

CI/CD UI for pipelines, jobs, and builds. Log in with the local user **admin** / **admin** (from `CONCOURSE_ADD_LOCAL_USER`; change if you configured differently). Configure pipelines via the UI or by setting the pipeline from the Concourse fly CLI targeting this URL.

### Gitea — https://git.bry.an

Git repos and package registry. On first visit you create the admin user and complete initial setup. After that: repos, package registry, and Git over HTTPS (and SSH on port 2222 if exposed).

### PgAdmin — https://pg.bry.an/pgadmin4/

PostgreSQL admin UI. Use the path **/pgadmin4/** (nginx redirects `https://pg.bry.an/` to that path). Log in with **admin@example.com** / **admin**. Add a server for the internal Postgres (host: `postgres`, or the host's Docker network name if you're not inside the stack) for Gitea/Concourse databases.

### Prometheus — https://metrics.bry.an

Monitoring and metrics. Prometheus scrapes Consul, Nomad, Vault, Gitea, and Concourse. Use the UI to run PromQL queries, view **Status → Targets** for scrape status, and explore metrics. No login by default. See **setup.md** § 2.7 for token setup (Consul and Vault metrics require the same tokens used elsewhere in the stack).

### Grafana — https://dash.bry.an

Dashboard UI for metrics. Grafana is pre-configured with Prometheus as the default data source, so you can create dashboards with multiple panels, set a refresh interval (e.g. 5s, 30s), and resize graphs. Log in with **admin** / **admin** (change on first use if you prefer). Create a new dashboard and add panels that query the Prometheus data source.

---

## When a token expires

**Consul ACL token** — Tokens issued by Vault (e.g. `vault read consul/creds/admin`) have a TTL and eventually expire. When that happens:

1. **Get a new token:** Log in to Vault (`vault login` with a valid Vault token, or sign in at https://vault.bry.an), then run `vault read consul/creds/admin` and copy the new token.
2. **Host and Compose stack:** Set `CONSUL_TOKEN` to the new value in your environment and restart the services that use it (e.g. `docker compose up -d` so `consul-template` and `nomad-server` pick up the new token). If you use a `.env` or shell export for `CONSUL_TOKEN`, update that and restart.
3. **Consul UI:** At https://consul.bry.an, log out or open the UI in a fresh session, then log in again with the new token.
4. **Nomad workers:** On each external worker, update the Consul token in the Nomad client config (`consul.token` in the client HCL, e.g. from **fedora-utm-worker.md**). Restart the Nomad client on that worker so it re-registers with Consul using the new token.

**Vault token** — If your Vault token expires, use "Sign in" at https://vault.bry.an with a valid token (e.g. root token or one from your auth method), or run `vault login` on the CLI.

---

## If Nomad raft state is broken

If Nomad's Raft state is corrupted and can't be fixed (e.g. the UI or CLI show persistent raft errors and recovery isn't feasible), you can reset Nomad and start clean:

1. **Shut down the stack:** `docker compose down`
2. **Remove Nomad server data** so the server can bootstrap fresh: delete or clear the Nomad server data volume (e.g. the volume backing `nomad_server_data` in `docker-compose.yml`). With Docker Compose you can run `docker volume rm mini-cloud_nomad_server_data` (or the project-prefixed name shown by `docker volume ls`) after the stack is down.
3. **Start the stack again:** `docker compose up -d`
4. **Unseal Vault** — Vault starts sealed after a restart. Unseal it (see **setup.md** § 2.5): `export VAULT_ADDR="https://vault.bry.an"` then `vault operator unseal` three times with three of your unseal keys.
5. **Re-submit jobs** — job definitions are gone with the wiped state; run your job files again (e.g. `nomad job run nomad/examples/nginx.hcl`). Consul still has the service mapping (and consul-template still uses it); once the job is running again, Nomad registers the service in Consul and the application is accessible again via the service name defined in your Nomad job config.

This is a last resort for a dev/mini-cloud environment. For production, HashiCorp recommends proper backup and recovery procedures: see [Recover from an outage](https://developer.hashicorp.com/nomad/docs/manage/outage-recovery) (snapshots, multi-server clusters, and outage recovery).

---

## Debugging and diagnosis

Aside from workers (which run on separate VMs), every component in the stack runs in a container on the host. On the host you can run `docker ps` to see which containers are running, and `docker logs <service_name>` (e.g. `docker logs nginx`) to view a container's logs. When everything is healthy, `docker ps` should show all stack containers up; example:

```
CONTAINER ID   IMAGE                      STATUS                 PORTS                          NAMES
a1b2c3d4e5f6   nginx                      Up 2 hours             80->80/tcp, 443->443/tcp       nginx
b2c3d4e5f6a1   hashicorp/consul-template  Up 2 hours                                            consul-template
c3d4e5f6a1b2   hashicorp/vault            Up 2 hours             8200->8200/tcp                 vault
d4e5f6a1b2c3   postgres                   Up 2 hours (healthy)                                  postgres
e5f6a1b2c3d4   gitea/gitea                Up 2 hours             2222->22/tcp                   gitea
f6a1b2c3d4e5   concourse/concourse        Up 2 hours                                            concourse-web
a2b3c4d5e6f1   concourse/concourse        Up 2 hours                                            concourse-worker
b3c4d5e6f1a2   hashicorp/consul            Up 2 hours (healthy)                                  consul
c4d5e6f1a2b3   hashicorp/nomad             Up 2 hours             4647->4647/tcp                 nomad-server
d5e6f1a2b3c4   dpage/pgadmin4             Up 2 hours                                            pgadmin
```

To run commands inside a container or open a shell, use `docker exec` as below.

**Run a one-off command:**

```bash
docker exec <container_name> <command>
```

**Open a shell in the container** (use `sh` for Alpine-based images like nginx, or the shell the image provides):

```bash
docker exec -it nginx sh
docker exec -it nomad-server sh
docker exec -it consul sh
docker exec -it vault sh
```

Container names match the service names in `docker-compose.yml`: `nginx`, `consul`, `vault`, `nomad-server`, `concourse-web`, `concourse-worker`, `gitea`, `pgadmin`, `postgres`, `consul-template`.

**Check status of key services from inside the container:**

- **Nomad server:** `docker exec nomad-server nomad agent info` or `docker exec nomad-server nomad server members`
- **Consul:** `docker exec consul consul members` (cluster members), `docker exec consul consul catalog services` (registered services). With ACLs you may need to pass a token; from the host you can use the Consul UI or CLI against https://consul.bry.an instead.
- **Vault:** From the host (with `VAULT_ADDR="https://vault.bry.an"` set), `vault status`. From inside the container: `docker exec vault vault status` (uses default local address).
- **Nginx:** `docker exec nginx nginx -t` to test the config; check `docker exec nginx cat /etc/nginx/nginx.conf` or list `/etc/nginx/conf.d` and `/etc/nginx/upstreams` to see what's loaded.

**Container logs** — To see what a container is doing, use `docker logs <container_name>`. Add `-f` to follow. For example: `docker logs nginx`, `docker logs nomad-server`, `docker logs consul`.

**Removing a stale Consul check** — After purging a Nomad job or restarts, a health check can remain in Consul and keep the service showing unhealthy. To remove that check by ID (use the CheckID from the Consul UI): (1) Get the node: `curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" "$CONSUL_HTTP_ADDR/v1/health/checks/example-server" | jq -r '.[] | select(.CheckID == "<CHECK_ID>") | .Node'`. (2) Deregister the check: `curl -X PUT "$CONSUL_HTTP_ADDR/v1/catalog/deregister" -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" -H "Content-Type: application/json" -d '{"Node":"<NODE_ID>","CheckID":"<CHECK_ID>"}'`. Replace `<CHECK_ID>` and `<NODE_ID>` with the values from step 1 and the Consul UI.

**Using journalctl** — On a **Linux host**, the Docker (or containerd) service is managed by systemd; use `journalctl -xeu docker.service` or `journalctl -xeu containerd.service` to inspect container runtime messages and errors. On **worker VMs** (e.g. Fedora as in **fedora-utm-worker.md**), Nomad and Consul run as systemd units: use `journalctl -xeu nomad` or `journalctl -xeu consul` to see recent logs and errors for those services. The `-xeu` options add context and show only recent output; drop `-u nomad` to see all system logs, or use `-f` to follow.
