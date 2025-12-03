# Reticulo – Bastille Template for Reticulum, NomadNet & MeshChat

This Bastille template provisions a FreeBSD jail with:

- **Reticulum (RNS)** – networking stack and `rnsd` daemon  
- **NomadNet** – terminal-based messaging/board system over Reticulum  
- **Reticulum MeshChat** – web UI for chat over Reticulum, built with Node/Vite

Everything is installed and wired up automatically inside the jail, including a
Python virtualenv for MeshChat and an rc.d script to run it as a service.

---

## What this template does

When applied to a jail, the template:

1. Installs base packages:

   ```text
   python311 py311-pip git node npm py311-sqlite3
   ```

2. Copies in and runs the installer script:

   - `root/install_rns_nomadnet_meshchat.sh`  
     - Installs **Reticulum (RNS)** via `pip`
     - Ensures a matching `pyXY-cryptography` package is installed via `pkg`
     - Installs **NomadNet** via `pkg` (if available) or `pip`
     - Clones **MeshChat** into `/opt/reticulum-meshchat`
     - Creates a Python virtualenv in `/opt/reticulum-meshchat/venv`
     - Installs MeshChat’s Python requirements into that venv
     - Generates a default `~/.reticulum/config` if one doesn’t exist

3. Installs the MeshChat rc.d script:

   - Copies `root/usr/local/etc/rc.d/meshchat` → `/usr/local/etc/rc.d/meshchat`
   - Marks it executable

4. Builds the MeshChat frontend:

   ```sh
   cd /opt/reticulum-meshchat
   npm install --omit=dev
   npm run build-frontend
   ```

   This creates the production static files under `public/`.

5. Enables services in `rc.conf`:

   ```sh
   sysrc meshchat_enable=YES
   sysrc reticulum_enable=YES
   ```

6. Adds port forwards from the host into the jail:

   - `host:1022  → jail:22`      (SSH)
   - `host:8000 → jail:8000`    (MeshChat web UI)

> **Note:** Port forwarding is handled by Bastille’s `RDR` directives in the
> Bastillefile and assumes you are using Bastille’s NAT mode / pf integration.

---

## Repository layout

```text
.
├── Bastillefile # Bastille template definition
├── README.md
└── root
    ├── install_rns_nomadnet_meshchat.sh # Main installer
    └── usr
        └── local
            └── etc
                └── rc.d
                    └── meshchat # rc.d script for MeshChat

```

---

## Requirements

- **Host OS:** FreeBSD with Bastille installed  
- **Jail:** A running jail created via Bastille (e.g. 14.3-RELEASE)  
- Network access from the jail to:
  - `pkg` repositories
  - GitHub (for MeshChat clone)  
- PF / NAT configured so Bastille can apply its `RDR` rules

---

## Quick start

### 1. Create a jail (example)

```sh
bastille create reticulo 14.3-RELEASE 10.0.0.42
bastille start reticulo
```

### 2. Apply the template

```sh
bastille template reticulo https://git.eldapper.com/matuzalem/Reticulo.git
```

Or via SSH:

```sh
bastille template reticulo git@giteavnet.eldapper.com:matuzalem/Reticulo.git
```

### 3. Start the jail services

```sh
bastille console reticulo
service reticulum start
service meshchat start
```

---

## Accessing MeshChat

```
http://<host-ip>:8000/
```

SSH into the jail:

```sh
ssh -p 1022 root@<host-ip>
```

---

## Reticulum configuration

Default config path: `~/.reticulum/config`

Edit interfaces as needed and restart:

```sh
service reticulum restart
```

---

## Updating MeshChat

```sh
bastille console reticulo
cd /opt/reticulum-meshchat
git pull
npm install --omit=dev
npm run build-frontend
. venv/bin/activate
pip install --upgrade -r requirements.txt
deactivate
service meshchat restart
```

---

## Notes

- Avoids Rust build by using pkg-installed `pyXY-cryptography`
- MeshChat’s venv uses system site-packages to reuse jail Python modules

---

## License

Add your preferred license here.
