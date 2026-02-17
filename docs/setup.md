# Setup

Steps needed before the stack is usable: install required software, prepare certs and hostfile, start the stack, then bootstrap (unseal Vault, bootstrap Nomad ACLs, and generate initial tokens) and complete any manual steps such as bringing up workers.

---

## 1. Software to install (host)

| URL | Description |
|-----|-------------|
| [colima.run](https://colima.run) | Colima — container runtime (Linux VM + Docker API) on macOS; e.g. `brew install colima` then `colima start`. Provides the Docker engine and CLI. |
| [docs.docker.com/compose/install](https://docs.docker.com/compose/install) | Docker Compose — runs the multi-service stack in `docker-compose.yml`. Install the standalone CLI if your Colima setup doesn't include it. |
| [github.com/FiloSottile/mkcert](https://github.com/FiloSottile/mkcert) | mkcert — generates locally trusted TLS certificates for the `*.bry.an` hostnames. Install the local CA with `mkcert -install` after installing (e.g. `brew install mkcert`). |
| [developer.hashicorp.com/nomad/downloads](https://developer.hashicorp.com/nomad/downloads) | Nomad CLI — submit and manage jobs from the host (e.g. the example in `nomad/examples/`). |
| [developer.hashicorp.com/consul/downloads](https://developer.hashicorp.com/consul/downloads) | Consul CLI — inspect the service catalog and health from the host. |
| [developer.hashicorp.com/vault/downloads](https://developer.hashicorp.com/vault/downloads) | Vault CLI — log in and read or write secrets from the host. |

---

## 2. Prepare before starting containers

### 2.1 TLS certificates (required)

Nginx expects certificate and key files in a local `ssl/` directory, mounted at `/etc/nginx/ssl`. You must create `ssl/` and generate certs for every hostname the stack uses.

**Hostnames that need certs:**

- `git.bry.an` (Gitea)
- `ci.bry.an` (Concourse)
- `pg.bry.an` (PgAdmin)
- `consul.bry.an` (Consul)
- `nomad.bry.an` (Nomad)
- `vault.bry.an` (Vault)
- `example.bry.an` (example Nomad service)
- `metrics.bry.an` (Prometheus)
- `dash.bry.an` (Grafana)
- `logs.bry.an` (Loki API)

Example — generate one cert per hostname in `ssl/` (filenames must match what nginx expects, e.g. `git.bry.an.pem` and `git.bry.an-key.pem`):

```bash
cd /path/to/mini-cloud
mkdir -p ssl
domains=(git.bry.an ci.bry.an pg.bry.an consul.bry.an nomad.bry.an vault.bry.an example.bry.an metrics.bry.an dash.bry.an logs.bry.an)
for d in "${domains[@]}"; do
  mkcert -cert-file "ssl/${d}.pem" -key-file "ssl/${d}-key.pem" "$d"
done
```

Do not commit private keys or `ssl/` to version control; add `ssl/` to `.gitignore` if it isn't already.

**Which computers need the mkcert root CA?**  
Any machine that **connects as an HTTPS client** to the mini-cloud must trust the mkcert CA, or TLS verification will fail (or the browser will show certificate errors):

- **The host** where the stack runs — if you open https://git.bry.an (etc.) in a browser on that machine, run `mkcert -install` on the host so the system trust store includes the mkcert root.
- **Any other machine you use to browse** the UIs (e.g. your laptop if the stack runs on a different box) — copy the root CA to that machine and configure your client to use it (see below).
- **External Nomad workers** (e.g. Fedora VMs) — if they talk to Consul or other services over HTTPS (e.g. `consul.bry.an:443`), those clients need to trust the cert; copy the root CA to each worker and point the client at it (see below).
- **Gitea container** — if you use Gitea Actions (e.g. artifact containers that call back to HTTPS URLs signed with mkcert), copy your mkcert root CA into `ssl/` (e.g. `cp "$(mkcert -CAROOT)/rootCA.pem" ssl/`), then recreate the Gitea container so it installs the cert at startup.

The nginx container does **not** need the root CA; it only needs the certificate and key files in `ssl/`. The CA is for **clients** that validate the server's cert.

**Copy the root CA to another machine (run on the mini-cloud host as root):**

```bash
scp "$(mkcert -CAROOT)/rootCA.pem" root@TARGET_HOST:/root/rootCA.pem
```

Install the copied root cert using the operating system (not mkcert on the target):

**macOS (target):**

```bash
sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain /root/rootCA.pem
```

**Fedora (target):**

```bash
sudo cp /root/rootCA.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

### 2.2 Hostfile (required for browser access)

You can use any domain names you like. So that `https://git.bry.an`, `https://consul.bry.an`, etc. resolve to the host (and thus to nginx), add entries to your hosts file.

On macOS/Linux, edit `/etc/hosts` (needs sudo). Add:

```
127.0.0.1 git.bry.an ci.bry.an pg.bry.an consul.bry.an nomad.bry.an vault.bry.an example.bry.an metrics.bry.an dash.bry.an logs.bry.an
```

If you run the stack on another machine and access it from your laptop, use that machine's IP instead of `127.0.0.1`.

If you use non-standard TLDs (e.g. `.bry.an`), many browsers will treat them as search terms instead of URLs. Configure your browser so that these domains are passed through to the address bar as `https://` URLs rather than triggering a search (e.g. in Chrome: Settings → Search engine → Manage search engines → add a shortcut that sends the query to a URL). While not a direct concern of the stack itself, if the browser or OS resolves these hostnames via public DNS instead of the hostfile, the URL can be sent to third parties (e.g. search or DNS providers) and effectively published; keeping traffic on the hostfile and using `https://` in the bar helps avoid that.

### 2.3 Concourse keys (included)

Concourse needs TSA and worker key pairs. This repo includes pre-generated keys under `concourse/keys/web/` and `concourse/keys/worker/` so you can run the stack immediately without extra steps. You can use these keys and the default users (e.g. Concourse admin, PgAdmin, Gitea/Concourse DB passwords in `docker-compose.yml`) as-is. The keys are committed for convenience only; if you prefer your own, run `concourse/generate-keys.sh` and replace the contents of `concourse/keys/web/` and `concourse/keys/worker/`.

### 2.4 External Nomad workers (optional)

If you run Nomad **clients** on separate VMs (e.g. Fedora in UTM):

- Install **Nomad** (and optionally **Consul**) on each worker.
- Use a container runtime the Nomad Docker task driver can talk to (e.g. **Podman** with `unix:///run/podman/podman.sock` or **Docker**).
- Copy and adapt `nomad/client.hcl` (set `client.servers` and Consul address to your host's IP).
- Ensure the host can reach the workers (and workers can reach the host) on the required ports (e.g. 4647 for Nomad RPC, 8500 or 443 for Consul). See **architecture.md** for routing and TLS details. For a step-by-step Fedora 43 UTM worker guide, see **fedora-utm-worker.md**.

You do **not** need external workers to start the Compose stack; the stack runs the Nomad **server** in Docker. Workers are only needed to run scheduled jobs (e.g. the example nginx service).

### 2.5 Unlocking Vault (after the stack is running)

Vault starts **sealed**. You must unseal it before it can serve secrets or run the Consul ACL setup.

**First time only — initialize Vault and get unseal keys and root token:**

```bash
export VAULT_ADDR="https://vault.bry.an"
vault operator init
```

Store the **unseal keys** and **root token** somewhere safe. You will need 3 of the 5 unseal keys to unseal (and the root token to log in or run the Consul ACL script).

**After every Vault restart — unseal (use 3 of the 5 keys):**

```bash
export VAULT_ADDR="https://vault.bry.an"
vault operator unseal   # paste key 1, run again
vault operator unseal   # paste key 2, run again
vault operator unseal   # paste key 3; Vault should report "Sealed: false"
```

**Optional — configure Vault to issue Consul ACL tokens:**

```bash
export VAULT_ADDR="https://vault.bry.an"
docker exec -e VAULT_TOKEN='<root-token>' vault sh /vault/scripts/setup-consul-acl.sh
```

After that, you can get a token for the Consul UI with: `vault read consul/creds/admin`.

### 2.6 Nomad ACL bootstrap (required)

The Nomad server runs with ACLs enabled. You must bootstrap Nomad ACLs once, then configure Vault to issue Nomad tokens so that only authorized users can submit jobs.

**Bootstrap Nomad ACL (one time only):**

1. Ensure the stack is running and Nomad is up. Set the Nomad API address (use the URL that reaches your Nomad server, e.g. via nginx):
   ```bash
   export NOMAD_ADDR="https://nomad.bry.an"
   ```
2. Run the bootstrap command. You will get a **Secret ID** and an **Accessor ID**. Save the **Secret ID**; it is the management token and is shown only once.
   ```bash
   nomad acl bootstrap
   ```
3. Store the Secret ID in your environment for the next step and for later use:
   ```bash
   export NOMAD_TOKEN="<secret-id-from-above>"
   ```

**Create a Nomad policy (e.g. for job submitters):**

Create a policy that allows submitting and managing jobs. Example — save as `nomad-job-submitter.hcl`:

```hcl
namespace "default" {
  capabilities = ["submit-job", "read-job", "list-jobs", "dispatch-job", "read-logs"]
}
```

Apply it (use the management token):

```bash
export NOMAD_ADDR="https://nomad.bry.an"
export NOMAD_TOKEN="<your-management-secret-id>"
nomad acl policy apply -description "Allow submitting jobs" job-submitter nomad-job-submitter.hcl
```

**Configure Vault to issue Nomad ACL tokens:**

Set your Vault root (or admin) token and the Nomad management token, then run the setup script inside the Vault container. The script is bind-mounted at `/vault/scripts/setup-nomad-secrets.sh` (no image rebuild needed). If you get "No such file or directory", recreate the Vault container so it picks up the mount: `docker compose up -d vault`.

```bash
export VAULT_ADDR="https://vault.bry.an"
export VAULT_TOKEN="<your-vault-root-token>"
export NOMAD_TOKEN="<your-nomad-management-secret-id>"
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" -e NOMAD_TOKEN="$NOMAD_TOKEN" vault sh /vault/scripts/setup-nomad-secrets.sh
```

By default this creates a Vault role `job-submitter` that issues tokens with the Nomad policy `job-submitter`. To get a Nomad token for job submission: `vault read nomad/creds/job-submitter` and use the `secret_id` as `NOMAD_TOKEN` when running `nomad job run ...`. You can override the policy/role with `NOMAD_POLICY` and `NOMAD_ROLE` when running the script.

**Allow Nomad to provision secrets to jobs:**  
The Nomad server is configured with a Vault block so that jobs can request secrets (e.g. `vault { policy = ["my-policy"] }` in a task, or `template` with `vault` in the stanza). For this to work, Nomad needs a Vault token with permission to create tokens for the policies your jobs use. Set that token when starting the stack:

```bash
export NOMAD_VAULT_TOKEN="<vault-token-with-token-creation-capability>"
docker compose up -d
```

You can use the Vault root token for development, or create a Vault policy that allows `auth/token/create` (or the specific role/policies your Nomad jobs need) and use a token with that policy. If `NOMAD_VAULT_TOKEN` is unset, Nomad still starts but jobs that request Vault secrets will fail to get tokens.

### 2.7 Consul certificate and token

**TLS certificate for Consul (https://consul.bry.an)**  
The certificate for the Consul UI is the same one you generated in **2.1** — `consul.bry.an` is in the `domains` list. Nginx uses `ssl/consul.bry.an.pem` and `ssl/consul.bry.an-key.pem`. No extra step unless you use different domain names.

**Consul ACL token (for UI or Nomad/client config)**  
If ACLs are enabled (as in this stack), the Consul UI and any client (e.g. Nomad workers) need a token. After unlocking Vault and running the Consul ACL setup script (see **2.5**), generate a token:

```bash
export VAULT_ADDR="https://vault.bry.an"
vault login   # use your root token, or another token with permission to read consul/creds/admin
vault read consul/creds/admin
export CONSUL_TOKEN="<token-from-above>"
```

Set the token to `CONSUL_TOKEN` on your host; the Compose stack expects this variable to be set after you obtain a token from Vault. Use the same token value in the Consul UI (https://consul.bry.an → Log in) or in your Nomad client config (`consul.token`). The `consul-template` and `nomad/client.hcl` in this repo use a bootstrap token; for production you'd use tokens from Vault (e.g. `consul/creds/admin` or a custom role).

### 2.8 Prometheus and metrics (optional)

**Prometheus** is included in the stack for monitoring. It scrapes metrics from Consul, Nomad, Vault, Gitea, and Concourse. The UI is available at **https://metrics.bry.an** (add `metrics.bry.an` to your hostfile and TLS certs as in § 2.1 and § 2.2). **Grafana** at **https://dash.bry.an** uses Prometheus as its data source for dashboards; add `dash.bry.an` to the same hostfile and certs so you can open it in a browser.

- **Consul metrics:** Prometheus uses `CONSUL_HTTP_TOKEN` (same as the variable used by consul-template) to scrape Consul’s `/v1/agent/metrics` endpoint. No extra step if you already set the Consul token.
- **Vault metrics:** To scrape Vault’s `/v1/sys/metrics` endpoint, set `METRICS_VAULT_TOKEN` in your environment to a Vault token that has read permission on `sys/metrics`. If you use the root token or a token with full access, it will work; otherwise create a Vault policy that allows `read` on `sys/metrics` and use a token with that policy. If `METRICS_VAULT_TOKEN` is unset, the Vault scrape target will fail in Prometheus (other targets will still work).
