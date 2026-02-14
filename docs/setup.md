# Setup

Steps needed before the stack is usable: install required software, prepare certs and hostfile, start the stack, then bootstrap (e.g. unseal Vault and generate initial tokens) and complete any manual steps such as bringing up workers.

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

Example — generate one cert per hostname in `ssl/` (filenames must match what nginx expects, e.g. `git.bry.an.pem` and `git.bry.an-key.pem`):

```bash
cd /path/to/mini-cloud
mkdir -p ssl
domains=(git.bry.an ci.bry.an pg.bry.an consul.bry.an nomad.bry.an vault.bry.an example.bry.an)
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
127.0.0.1 git.bry.an ci.bry.an pg.bry.an consul.bry.an nomad.bry.an vault.bry.an example.bry.an
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

### 2.6 Consul certificate and token

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

---

## 3. Quick checklist

Before running `docker compose up`:

- [ ] Docker (or Colima) and Docker Compose installed and running.
- [ ] mkcert installed and `mkcert -install` run.
- [ ] `ssl/` directory created and certs (and keys) in place for all hostnames, with filenames matching nginx config (e.g. `git.bry.an.pem`, `git.bry.an-key.pem`).
- [ ] Hostfile updated so `*.bry.an` resolves to the host (e.g. `127.0.0.1`).

Then start the stack:

```bash
docker compose up -d
```

See **../README.md** for what the stack does and **architecture.md** for how the pieces fit together.
