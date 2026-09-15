# Server Connector

Bootstrap a fresh Ubuntu or Debian VPS into a **Chabokan** node: install system packages, Docker, [node-manager](https://github.com/chabokan/node-manager), harden the firewall, and register the server with your hub.

## Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 20.04+ or Debian 11+ |
| **Python** | Host `python3` must be 3.9–3.13; Ubuntu 20.04's default 3.8 needs an upgrade before bootstrap |
| **Privileges** | Must run as **root** |
| **Network** | Outbound HTTPS (GitHub, Docker Hub, hub API, country lookup) |
| **Inputs** | Node `TOKEN` and HTTPS hub hostname / origin (no path) |

## Quick start

```bash
# Interactive prompts for TOKEN and HUB_URL (read from /dev/tty)
curl -fsSL https://raw.githubusercontent.com/chabokan/server-connector/main/start.sh | bash

# Or pass arguments directly
bash start.sh <TOKEN> <HUB_URL>
```

Examples:

```bash
bash start.sh my-secret-token hub.chabokan.net
bash start.sh my-secret-token https://hub.example.com
```

## What it does

```
start.sh
  ├─ Base DNS, timezone (Asia/Tehran)
  ├─ Detect IP + country
  ├─ Iran path: Shecan DDNS + DNS (optional wait)
  ├─ Clone this repo → /var/server-connector
  └─ debian/ubuntu.sh  or  debian/debian.sh
        ├─ Packages (apt)
        ├─ Docker CE + compose
        ├─ node-manager (/var/ch-manager)
        ├─ System settings (dirs, cron, vsftpd)
        ├─ Firewall (iptables allowlist)
        └─ Connect to hub via local API :8123
```

On success, the node is registered with the hub and services are running under Docker Compose in `/var/ch-manager`. Iranian servers use Shecan DNS during provisioning and hub connection; after a successful connection, DNS is restored to `8.8.8.8` and `1.1.1.1`. A repeat install updates the existing Git checkouts without deleting `/var/ch-manager/sql_app.db`; a checkout with conflicting local changes causes the update to stop.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG` | `0` | Set to `1` for debug logs |
| `NO_COLOR` | — | Disable ANSI colors |
| `INSTALL_LOG` | `/var/log/server-connector-install.log` | Install log path |
| `SHECAN_DDNS_PASSWORD` | *(built-in)* | Shecan DDNS password (Iran servers) |
| `DDNS_WAIT_SECONDS` | `90` | Wait after DDNS update (Iran) |
| `DISABLE_IPV6` | `1` | Disable IPv6 via sysctl |
| `CLEANUP_CONFIGS` | `0` | Remove tracked config templates from the clone after apply; normally leave them in place so Git updates work |
| `ALLOWED_IPS_URL` | `https://chabokan.net/ips.txt` | Remote allowlist for firewall |
| `NODE_MANAGER_REPO` | `https://github.com/chabokan/node-manager` | Override node-manager git URL |
| `CONNECT_MAX_RETRIES` | `8` | Hub connect retry count |
| `CONNECT_RETRY_DELAY` | `5` | Seconds between connect retries |

Example:

```bash
DEBUG=1 DDNS_WAIT_SECONDS=60 bash start.sh "$TOKEN" hub.chabokan.net
```

## Repository layout

```
start.sh                 # Bootstrap entry point
lib/
  common.sh              # Logging, validation, DNS, retries
  docker.sh              # Docker + node-manager install
debian/
  ubuntu.sh / debian.sh  # OS orchestrators (stepped install)
  packages.sh            # apt packages
  settings.sh            # sysctl, cron, vsftpd
utilities/
  firewall.sh            # iptables rules
  final.sh               # Hub connect
  finall.sh              # Compatibility wrapper → final.sh
configs/
  vsftpd.conf
```

## Logging

- Colored step output on the terminal: `[INFO]`, `[WARN]`, `[ERROR]`, `[OK]`, `[1/6] …`
- Full install log with timestamps: `/var/log/server-connector-install.log`
- On failure, the trap prints the failing line/command and points at the log file

```bash
tail -f /var/log/server-connector-install.log
```

## Iran-specific behavior

If the public IP resolves to country `IR`:

1. Shecan DDNS is updated (`SHECAN_DDNS_PASSWORD`)
2. Script waits for propagation (`DDNS_WAIT_SECONDS`, with a visible countdown)
3. DNS is switched to Shecan (`178.22.122.101`, `185.51.200.1`)

Country detection is best-effort. If the lookup API is unreachable, install continues as non-IR (`COUNTRY=UNKNOWN`).

## After install

Useful paths and checks:

| Path / command | Purpose |
|----------------|---------|
| `/var/ch-manager` | node-manager + Compose stack |
| `/.env` | Runtime env for cron (`TOKEN`, `HUB_URL`, …) — mode `600` |
| `/builds`, `/storage`, `/backups` | Working directories |
| `docker compose -f /var/ch-manager/docker-compose.yml ps` | Service status |
| `curl -s http://127.0.0.1:8123` | Local API health |

Cron (configured by `settings.sh`):

- Daily: `git -C /var/server-connector pull --ff-only`
- Weekly: re-run package install script
- Every minute: host worker `server-queue.py` (if present); host commands and updates run here, while service jobs can also run in the web worker
- Nightly: `update_core.sh` (if present); uses the host virtual environment and refuses to discard local Git changes

## Troubleshooting

**Hub connect failed**

1. Confirm Compose is up: `cd /var/ch-manager && docker compose ps`
2. Hit the API: `curl -fsS http://127.0.0.1:8123/openapi.json`
3. Verify `TOKEN` / `HUB_URL` (re-run with correct args, or update `/.env` and retry `bash /var/server-connector/utilities/final.sh`; it loads `/.env` if the variables are not already exported)
4. Inspect `/var/log/server-connector-install.log`

**Locked out of SSH after firewall**

The installer leaves `/etc/ssh/sshd_config` unchanged and does not restart SSH. Firewall rules keep established sessions and allow new TCP connections on the SSH port reported by `sshd -T` and the port of the current SSH session (if available). If neither can be detected, the firewall step stops before changing any rules. Allowed Chabokan IPs are loaded from `ALLOWED_IPS_URL`.

**Docker install fails**

Pinned Docker versions fall back to the latest packages from Docker’s apt repository. Check the install log for the last apt/pip error lines.

**vsftpd / IPv6**

IPv6 is disabled by default; vsftpd is configured for IPv4 (`listen=YES`, `listen_ipv6=NO`). Set `DISABLE_IPV6=0` if you need IPv6.

## Security notes

- Requires root; replaces DNS, FTP, and iptables on the host. SSH configuration and its listening port are preserved.
- Prefer passing `SHECAN_DDNS_PASSWORD` via environment instead of relying on a baked-in default.
- `/.env` holds secrets; keep permissions `600` and do not commit it.

## License

Internal / project use for Chabokan node provisioning. See the repository owner for licensing terms.
