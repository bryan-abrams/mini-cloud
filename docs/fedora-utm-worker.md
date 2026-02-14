# Fedora 43 UTM worker for Nomad

This document describes how to run a **Nomad client** (worker) on a Fedora 43 VM in **UTM** on macOS. The worker joins the mini-cloud stack: it connects to the Nomad server and Consul on the host, runs containerized tasks (using Podman with runc), and registers services so nginx can proxy to them.

---

## 1. Download Fedora Server AARCH64

1. Open [getfedora.org](https://getfedora.org) (or [arm.fedoraproject.org](https://arm.fedoraproject.org)) and choose **Fedora Server**.
2. Select **AArch64** (ARM 64-bit) and download the **ISO image** (e.g. `Fedora-Server-dvd-aarch64-43-x.x.x.iso`).
3. Save the ISO somewhere on your Mac (e.g. `~/Downloads/`).

---

## 2. Create the VM in UTM and set networking

1. Open **UTM** and create a **New Virtual Machine**.
2. Choose **Virtualize** → **Linux**.
3. **Boot ISO image:** select the Fedora Server AARCH64 ISO you downloaded.
4. **Hardware:** assign enough RAM and CPU (e.g. 2 GB RAM, 2 cores). Storage: e.g. 20 GB.
5. **Network:**
   - Set the network mode to **Shared Network** so the VM gets an IP on the same segment as the host (e.g. `192.168.64.0/24` with the Mac at `192.168.64.1`).
   - Ensure the **MAC address is unique.** In UTM: select the VM → **Edit** → **Network** → **Advanced** → set or generate a unique MAC so this VM does not clash with others on the same network.
6. Finish the wizard and start the VM to begin installation.

---

## 3. Install Fedora (base system, container, headless management)

1. Boot from the ISO. At the installer welcome screen, choose **Install to Hard Drive**.
2. **Installation summary:**
   - **Language & keyboard:** set as desired.
   - **Time & date:** set timezone.
   - **Installation destination:** select the disk and accept (optionally encrypt or customize partitions if you prefer).
   - **Software selection:** choose:
     - **Minimal install** (base system), and add:
       - **Container management** (Podman and related tools).
       - **Headless management** (e.g. SSH, tools useful for managing the VM without a local console).
3. **Root password** and/or **User creation:** set a user and enable SSH access if you use headless management.
4. Start the installation and wait for it to finish, then reboot and eject the ISO so the VM boots from the new system.

---

## 4. After first boot: network and addresses

1. Log in (console or SSH).
2. Ensure the VM is on the **shared network** and has a stable IP (e.g. from DHCP on `192.168.64.0/24`). Check with:
   ```bash
   ip -4 addr show
   ```
   Note the primary address (e.g. `192.168.64.15`). You will use this as `bind_addr` and in `advertise` in the Nomad client config.
3. Ensure the VM can reach the host (e.g. `192.168.64.1`) and that the host can reach the VM. From the VM:
   ```bash
   ping -c 2 192.168.64.1
   ```
4. **(Optional but recommended)** Add a static DHCP reservation or fix the VM's IP in your router/UTM so the address does not change after reboot.

---

## 5. Trust the mini-cloud TLS CA (for Consul HTTPS)

Workers talk to Consul at `consul.bry.an:443`. If that uses a certificate signed by **mkcert**, the VM must trust the mkcert root CA or TLS verification will fail.

On the **mini-cloud host** (Mac), copy the root CA to the VM:

```bash
scp "$(mkcert -CAROOT)/rootCA.pem" root@VM_IP:/root/rootCA.pem
```

On the **Fedora VM**:

```bash
sudo cp /root/rootCA.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

Replace `VM_IP` with the VM's actual IP (e.g. `192.168.64.15`).

---

## 6. Copy and adapt the Nomad client config

1. On your **host** (or from this repo), copy the example client config to the VM:
   ```bash
   scp /path/to/mini-cloud/nomad/client.hcl root@VM_IP:/tmp/client.hcl
   ```
2. On the **VM**, move it into place and edit:
   ```bash
   sudo mkdir -p /etc/nomad.d
   sudo mv /tmp/client.hcl /etc/nomad.d/client.hcl
   sudo vi /etc/nomad.d/client.hcl
   ```
3. Set these to the **VM's** shared-network IP (e.g. `192.168.64.15`):
   - **`bind_addr`** — the VM's IP.
   - **`advertise.http`** — `VM_IP:4646`.
   - **`advertise.rpc`** — `VM_IP:4647`.
4. Set **`client.servers`** to the **host's** IP and Nomad RPC port (e.g. `["192.168.64.1:4647"]`). The host is typically the shared network gateway.
5. **Consul:** the example uses `consul.bry.an:443` with `ssl = true`. Put the **Consul ACL token** (from Vault, e.g. `vault read consul/creds/admin`) into **`consul.token`** so the client can register with Consul. See **setup.md** § 2.6 for how to obtain the token.
6. Save the file. Example (replace `192.168.64.15` and `192.168.64.1` with your VM and host IPs):

   ```hcl
   datacenter = "dc1"
   region     = "global"
   data_dir   = "/opt/nomad/data"
   bind_addr  = "192.168.64.15"

   advertise {
     http = "192.168.64.15:4646"
     rpc  = "192.168.64.15:4647"
   }

   client {
     enabled = true
     servers = ["192.168.64.1:4647"]
   }

   consul {
     address = "consul.bry.an:443"
     ssl     = true
     token   = "YOUR_CONSUL_TOKEN"
   }

   plugin "docker" {
     config {
       endpoint          = "unix:///run/podman/podman.sock"
       allow_privileged  = false
     }
   }
   ```

Ensure the VM can resolve `consul.bry.an` (e.g. add it to `/etc/hosts` on the VM to point to the host IP, or use DNS that resolves it to the host).

---

## 7. Use runc as the OCI runtime and configure Podman

Nomad's Docker task driver talks to Podman over its socket. Podman uses an **OCI runtime** to run containers; **runc** is the default and is recommended.

1. **Install runc** (usually provided by the container stack):
   ```bash
   sudo dnf install -y runc
   ```
2. **Confirm Podman is using runc:** Podman on Fedora typically uses runc by default. Check:
   ```bash
   podman info --format '{{.Host.OCIRuntime.Path}}'
   ```
   You should see a path to `runc`.
3. **Configure Podman (optional):** To force runc or tune settings, edit the Podman config. For the current user:
   ```bash
   mkdir -p ~/.config/containers
   # Or for system-wide (so Nomad's agent can use it when running as root or a service user):
   sudo mkdir -p /etc/containers
   ```
   Create or edit `containers.conf` (user: `~/.config/containers/containers.conf`, system: `/etc/containers/containers.conf`). Example (system-wide so the Nomad agent uses it):
   ```ini
   [engine]
   runtime = "runc"

   [engine.runtimes.runc]
   runtime_path = ["/usr/bin/runc"]
   ```
   If the Nomad agent runs as **root**, use `/etc/containers/containers.conf`. If it runs as a dedicated user, ensure that user's Podman socket and config use runc (e.g. rootful Podman with `unix:///run/podman/podman.sock`).
4. **Socket for Nomad:** The client config uses `unix:///run/podman/podman.sock`. That is the default for **rootful** Podman. Ensure the Nomad agent runs as a user that can access this socket (typically root), or switch to rootless socket and update the plugin `endpoint` in `client.hcl` (rootless socket is usually under the user's XDG runtime).

---

## 8. Install the Nomad CLI on the worker

You need the Nomad binary on the VM so you can run `nomad agent -config=...`.

1. Add the HashiCorp repo and install Nomad (adjust version/arch as needed for Fedora 43 AARCH64):
   ```bash
   sudo dnf install -y dnf-plugins-core
   sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
   sudo dnf install -y nomad
   ```
2. Verify:
   ```bash
   nomad version
   ```

---

## 9. Run the Nomad agent

Run the agent with the client config:

```bash
sudo nomad agent -config=/etc/nomad.d/client.hcl
```

For production, run it as a **systemd** service so it starts on boot and restarts on failure.

1. Create a unit file:
   ```bash
   sudo tee /etc/systemd/system/nomad.service << 'EOF'
   [Unit]
   Description=Nomad client agent
   Documentation=https://www.nomadproject.io/
   After=network-online.target
   Wants=network-online.target

   [Service]
   ExecStart=/usr/bin/nomad agent -config=/etc/nomad.d/client.hcl
   ExecReload=/bin/kill -HUP $MAINPID
   KillMode=process
   KillSignal=SIGINT
   LimitNOFILE=65536
   Restart=on-failure
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   EOF
   ```
2. Enable and start:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable nomad
   sudo systemctl start nomad
   sudo systemctl status nomad
   ```

On the **host**, run `nomad node status` (with `NOMAD_ADDR` pointing at the Nomad server) to confirm the new client appears. In the Consul UI (https://consul.bry.an), the Nomad client's HTTP check should become healthy once the agent is running.

For how the worker fits into the stack (routing, Consul, nginx), see **architecture.md**. For obtaining the Consul token and TLS setup, see **setup.md**.
