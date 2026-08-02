# xray-proxy-install

<div align="center">

[中文](README.md) · **English**

</div>

---

VLESS + Reality + Vision + Fragment proxy one-click installer for cross-border e-commerce networks (v4.5.4). BBR optimization, auto Swap, Clash subscription, multi-distro support. Fragment splitting takes effect on the client subscription side only; the server no longer keeps an invalid fragment config.

[![GitHub](https://img.shields.io/badge/GitHub-Evergreen05/xray--proxy--install-blue?logo=github)](https://github.com/Evergreen05/xray-proxy-install)

## Quick Start

### Prerequisites

- A Linux server with **root** access
- Supported OS: Ubuntu 16.04+, Debian 9+, CentOS 7+, RHEL 7+, Rocky/Alma/Anolis 8+, Fedora 29+, openSUSE, Arch, Alpine (bash required)
- Kernel 4.9+ recommended (for BBR)
- Open ports in your cloud security group: **443**, **8443**, **8880**, **10707**
- `curl` or `wget` installed (most systems have them pre-installed)

### Option 1: One-Click Install (Recommended)

Run this on your server as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh)
```

Or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh | bash
```

### Option 2: Unattended Install (-y flag)

Skips all interactive prompts (does **not** auto-update system packages, does **not** configure Swap, uses 200Mbps default network parameters). `-y` mode is intended for repeated deployments or CI scenarios. To customize Swap size or network parameters, use interactive mode:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh) -y
```

### Option 3: Manual Download & Run

If you prefer to inspect the script first:

```bash
# Download
wget https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh

# (Optional) Review the script
# nano install.sh

# Make executable and run
chmod +x install.sh
bash install.sh
```

> **Tip**: After deployment, use `proxy-manager info` to view your subscription URL and node parameters.

## Features

- **Multi-protocol nodes**: Reality+Vision (primary/anti-detection), VLESS+TLS (backup), XHTTP+Reality (CDN-compatible); Fragment splitting is applied in the generated Clash subscription
- **Single-domain, single-port Reality**: Default fronting target is `cdn-dynmedia-1.microsoft.com:443`. The server only exposes one real Microsoft dynamic media CDN certificate on 443, avoiding the strong active-probing signature of multi-port/multi-site setups
- **Dest preflight at deploy time**: Step 7 uses `openssl s_client -tls1_3 -alpn h2` to verify the target. Failing domains are dropped; if all fail, the script auto-falls back through the backup pool. If the pool also fails, it warns and continues without blocking deployment
- **DNS optimization**: Client-side fake-ip + fallback-filter anti-pollution; server-side Xray built-in DoH resolution
- **Auto BBR optimization**: Intelligently calculates TCP buffer and connection queue parameters based on user-input bandwidth (Mbps) using a 100ms RTT formula
- **Swap configuration**: Interactive mode asks whether to configure and how much (MB), recommended at 2× physical RAM; unattended mode (-y) skips entirely (creation failure in containers does not abort deployment)
- **Clash subscription**: Auto-generates Clash Meta format subscription via Nginx HTTP endpoint
- **VLESS universal subscription**: Also generates base64-encoded `vless://` links (`nodes.txt` / `<sub-path>-vless` endpoint) for clients that do not support Clash Meta YAML (v2rayN/v2rayNG/Shadowrocket legacy versions)
- **Smart routing rules**: Powered by [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) (⭐ ~27.6k), auto-updated daily, whitelist mode with precise geo-routing
- **Auto certificates**: ECC P-256 self-signed certs (SAN covers all camouflage domains) with secure permission handling
- **Pinned version**: Xray-core installed at a fixed version (v26.3.27), auto-fallback to latest on failure
- **Config pre-check**: jq JSON validation + `xray run -test` semantic check before starting services
- **Clock detection**: Checks NTP sync before deployment (Reality handshake is time-sensitive)
- **Self-healing start**: Auto-repairs certificate permissions and retries if Xray fails to start
- **Cross-platform**: Supports apt/dnf/yum/pacman/zypper/apk (6 package managers). Alpine requires bash pre-installed and its OpenRC path is not fully tested
- **Cross-init**: Supports systemd/sysvinit/OpenRC (3 service managers)
- **Auto firewall**: Configures ufw/firewalld/iptables automatically (with rule persistence)
- **SELinux compatible**: Auto-sets httpd_sys_content_t on CentOS/RHEL/Anolis
- **Auto rollback**: Any failure triggers automatic rollback of all changes (restores previous config on overwrite installs)
- **Management CLI**: `proxy-manager` command for post-deploy administration (includes config test & subscription URL query)
- **Key fallback**: Multiple X25519 extraction and validation modes (JSON, regex, OpenSSL local generation, etc.), compatible with different Xray version outputs

## Supported Operating Systems

| Distro | Version | Package Mgr | Init System | Notes |
|--------|---------|-------------|-------------|-------|
| Ubuntu | 16.04+ | apt | systemd | |
| Debian | 9+ | apt | systemd | |
| CentOS | 7+ | yum/dnf | systemd | |
| RHEL | 7+ | yum/dnf | systemd | |
| Rocky Linux | 8+ | dnf | systemd | |
| AlmaLinux | 8+ | dnf | systemd | |
| Anolis OS (龙蜥) | 8+ | dnf | systemd | |
| Fedora | 29+ | dnf | systemd | |
| openSUSE | Leap 15+ / Tumbleweed | zypper | systemd | |
| Arch Linux / Manjaro | Rolling | pacman | systemd | |
| Alpine Linux | 3.12+ | apk | OpenRC | bash required, OpenRC path not fully tested |
| Amazon Linux | 2/2023 | yum/dnf | systemd | |
| openEuler (欧拉) | 20.03+ | dnf | systemd | |

> Container environments (OpenVZ/LXC): Swap creation failure will not abort deployment. Kernel 4.9+ required for BBR.

## Important Notes

- **Subscription is HTTP by default**: The generated subscription URL is `http://IP:10707/random-path`. HTTP is transmitted in plaintext and can be intercepted by middleboxes. Use it only on trusted networks, or download `/usr/share/nginx/html/clash.yaml` directly via SFTP/SCP. HTTPS requires your own domain and certificate. The safest option is to avoid the public subscription URL entirely and copy the config file locally with SFTP/SCP.
- **TLS nodes need skip-cert-verify**: Port 8443 uses a self-signed certificate; clients must enable `skip-cert-verify`.
- **Reality is the primary node**: The 443 Reality node requires no extra settings and is recommended for daily use; TLS and XHTTP serve as backup/compatibility nodes.

## Installation Process

The script runs through **14 steps** (plus a pre-check and final output):

| Step | Description |
|------|-------------|
| Pre | Root privilege check & distro detection |
| 1 | Acquire public IP + NTP clock sync check |
| 2 | Memory check & Swap configuration (interactive: asks whether to configure and size; -y: skips) |
| 3 | Environment check & port conflict detection (stop old services, cleanup, backup old config) |
| 4 | System update & dependency installation |
| 5 | Network kernel optimization (BBR/TCP/file descriptors; interactive: asks bandwidth for smart calculation; -y: uses defaults) |
| 6 | Install Xray-core (pinned version, fallback to latest) |
| 7 | Generate UUID, X25519 keypair, Short ID, subscription path; **preflight Reality dest (TLS1.3 + h2), auto-fallback to backup pool on failure** |
| 8 | Generate Xray config (3 inbounds: Reality + TLS + XHTTP) + config pre-check |
| 9 | Generate self-signed ECC certificates (SAN covers camouflage domains) with secure permissions |
| 10 | Generate Clash subscription config (3 nodes + DNS + routing rules) + VLESS universal subscription (`nodes.txt` / base64) |
| 11 | Configure Nginx subscription endpoints (Clash + VLESS) |
| 12 | Configure systemd limits & start services (with auto cert-permission repair) |
| 13 | Create `proxy-manager` CLI tool |
| 14 | Firewall rules & health checks |
| Output | Print deployment results, node list, subscription URL |

## Node Configuration

This release uses a **single-domain, single-port Reality** design: the default fronting target `cdn-dynmedia-1.microsoft.com:443` maps to one Reality inbound, plus TLS (8443) and XHTTP (8880) backup inbounds — **3 nodes** in total. Node names follow `<Type>-<CDN-Label>` (e.g. `Reality-Microsoft-CDN`).

- If the primary target fails preflight and a fallback domain is adopted, all three nodes share that fallback domain (e.g. `Reality-Apple-Update`, `TLS-Apple-Update`, `XHTTP-Apple-Update`) on different ports;
- To scale, append `domain|port|label` entries to the `REALITY_CDNS` array at the top of the script; the Reality/TLS/XHTTP groups will cascade automatically. Different Reality inbounds must use different ports and cannot all bind to 443.

| Camouflage CDN | Node Label | Reality Port | dest |
|----------------|-----------|--------------|------|
| cdn-dynmedia-1.microsoft.com | Microsoft-CDN | 443 | cdn-dynmedia-1.microsoft.com:443 |

| Type | Port | Protocol | Transport | Encryption | Purpose |
|------|------|----------|-----------|------------|---------|
| Reality | 443 | VLESS | TCP + Vision | Reality | Primary, anti-detection; subscription includes Fragment |
| TLS | 8443 | VLESS | TCP + Vision | TLS (self-signed) | Backup, SNI = Microsoft-CDN domain |
| XHTTP | 8880 | VLESS | XHTTP | Reality | CDN compatible, Reality security layer, SNI = Microsoft-CDN domain |

- **Fragment**: TLS Client Hello fragmentation (100-200 bytes, 10-50ms interval) for enhanced anti-detection; applied by the Clash Meta client from the subscription side, Xray server no longer configures fragment
- **Reality**: Single-domain, single-port — a probe only sees the real Microsoft dynamic media CDN certificate on 443. Default dest supports TLS1.3 + h2 with a clean certificate chain (Microsoft enterprise CA)
- **Vision**: XTLS Vision flow control for high performance
- **XHTTP**: HTTP/2-based XHTTP transport + Reality security layer (no self-signed cert needed), supports CDN relay
- **Proxy group**: Proxy → Reality / TLS / XHTTP sub-groups, manual `select` only — no url-test or fallback

## Reality Dest Selection & Self-Healing

### Why single-domain, single-port?

The previous release camouflaged 5 different sites (Apple, Microsoft, Bing) on 5 separate ports. In the Reality community this is considered a **strong active-probing signature**:

- A single IP “owning” multiple high-value CDN domains across different companies does not match real server behavior;
- Multi-port + multi-domain combinations are easily fingerprinted;
- Bing and Apple download CDNs are overused in tutorials and already noisy.

The new release converges to one domain on one port: the default dest `cdn-dynmedia-1.microsoft.com:443` matches a real-world Microsoft dynamic media CDN server — a probe only sees a clean enterprise CDN certificate.

### Dest preflight & fallback pool

During Step 7, `check_reality_dest` verifies each target with `openssl s_client -tls1_3 -alpn h2`:

1. If the primary target `cdn-dynmedia-1.microsoft.com` passes, it is used directly;
2. If it fails, the script tries the fallback pool in order: `updates.cdn-apple.com`, `iosapps.itunes.apple.com`, `download-porter.hoyoverse.com`, `osxapps.itunes.apple.com`, `music.apple.com`, `tv.apple.com`, `www.mi.com`, `buylite.music.apple.com`, `www.lamer.com.hk`; **only the first passing domain is adopted**, multiple fallback domains are not deployed simultaneously;
3. If the fallback pool also fails, the script warns but **continues deployment without blocking** (the server’s outbound may be restricted while the client side might still work), and defaults to the first fallback domain to generate the config.

This mechanism lets the script self-heal when the default domain becomes unavailable, without requiring manual code edits.

## Routing Rules

The generated Clash subscription uses [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) (⭐ ~27.6k), one of the most popular and well-maintained Clash rule sets.

| Rule Provider | Category | Behavior |
|--------------|----------|----------|
| `reject` | Ads, trackers, malware | REJECT |
| `private` | Private/LAN IPs, internal domains | DIRECT |
| `direct` | China mainland domains & IPs | DIRECT |
| `lancidr` | LAN CIDR ranges | DIRECT |
| `cncidr` | China CIDR ranges | DIRECT |
| `proxy` | Foreign/blocked domains | Proxy |
| `apple` | Apple services | Proxy |
| `google` | Google services | Proxy |
| `icloud` | iCloud services | Proxy |
| `telegramcidr` | Telegram IP ranges | Proxy |
| `applications` | App-level process rules | DIRECT |

**Key features:**
- Designed for **Clash Meta (mihomo)** kernel
- Compatible with Clash Verge Rev, mihomo Party, OpenClash (mihomo kernel), Shadowrocket (recent versions), Stash, etc. **Clash for Windows has been archived and does not support Reality/XHTTP/fragment — do not use it.**
- **Auto-updated every 24 hours** (rolling interval from the client's first fetch, not a fixed time of day)
- Reliable data sources: v2ray-rules-dat, domain-list-community, China IP list
- **Whitelist mode**: unmatched traffic defaults to proxy (MATCH=Proxy), ensuring all blocked sites go through the proxy

> The subscription URL is served over HTTP on port `10707` by default. For HTTPS, you can put Nginx/Caddy behind with a valid certificate.

> **Configurable rule source**: The default rule source is the jsdelivr CDN. If rule fetching fails on your network, edit the `RULES_CDN_PREFIX` variable at the top of `install.sh` — switch to GitHub direct (`https://raw.githubusercontent.com/Loyalsoldier/clash-rules@release`) or a ghproxy mirror, then redeploy.

## DNS Optimization

### Client-side (Clash Meta / mihomo)

- **fake-ip mode** (198.18.0.1/16): Faster connection setup; avoids connecting to poisoned IPs
- **fake-ip-filter**: Windows NCSI detection domains (msftconnecttest.com) and Apple service domains always get real IPs, preventing Windows from falsely reporting "No internet access" after TUN mode is disabled
- **Domestic nameservers**: 223.5.5.5 / 119.29.29.29 / 114.114.114.114 (plain UDP, fast resolution)
- **Fallback**: `1.1.1.1` / `8.8.8.8` (plain UDP)
- **fallback-filter**: GeoIP CN + geosite:gfw + 240.0.0.0/4 + specified domains (google/facebook/youtube) — blocked domains forced to fallback
- **respect-rules**: DNS queries follow the same routing rules as traffic. `1.1.1.1`/`8.8.8.8` does not match cncidr/GEOIP,CN → falls through to `MATCH,Proxy` at the end of the rule chain → DNS queries are sent through the proxy tunnel, where plain UDP is encrypted by the tunnel — no need for DoH double encryption (saves one TLS handshake, and no `dns.google` resolution dependency). **Caveat: this setup relies on the `MATCH,Proxy` fallback. Never add `1.1.1.1`/`8.8.8.8` to DIRECT/IP-CIDR rules, otherwise DNS queries will go plaintext direct and be poisoned by the GFW. If you cannot guarantee this after rule changes, switch back to DoH for safety.**
- **proxy-server-nameserver**: Proxy node domain resolution uses domestic DNS to avoid loops

### Server-side (Xray)

- Xray built-in DNS: `https://1.1.1.1/dns-query` + `https://dns.google/dns-query` (DoH)
- Freedom outbound `domainStrategy: UseIPv4` — immune to broken VPS resolvers or IPv6 fallback issues

## Post-Deployment Management

After deployment, use the `proxy-manager` command:

```bash
proxy-manager info       # Server info, subscription URL, node parameters
proxy-manager sub        # Print subscription URL only (easy to copy)
proxy-manager status     # Xray & Nginx service status, port monitoring
proxy-manager test       # Test Xray & Nginx config validity
proxy-manager start      # Start all services
proxy-manager stop       # Stop all services
proxy-manager restart    # Restart all services
proxy-manager config     # View Xray config (JSON formatted)
proxy-manager rules      # View Clash rules file path
proxy-manager log        # View last 50 lines of Xray logs
proxy-manager uninstall  # Completely uninstall (configs, certs, rules)
```

## Required Ports

Ensure these ports are open in your cloud security group/firewall before deployment:

| Port | Protocol | Purpose |
|------|----------|---------|
| 443 | TCP | Reality primary node - Microsoft-CDN (cdn-dynmedia-1.microsoft.com) |
| 8443 | TCP | VLESS TLS backup node (self-signed certificate) |
| 8880 | TCP | VLESS XHTTP CDN-compatible node (Reality security layer) |
| 10707 | TCP | Clash subscription HTTP endpoint (configurable) |

## Client Setup

The script generates two subscription formats — choose by client type:

### Subscription Endpoints

| Endpoint | Format | Suitable Clients |
|----------|--------|------------------|
| `http://IP:10707/<sub-path>` | Clash Meta YAML | Clash Meta / Mihomo / v2rayN 6.x+ |
| `http://IP:10707/<sub-path>-vless` | VLESS base64 universal subscription | v2rayN/v2rayNG/Shadowrocket legacy versions |

### Recommended Clients

- **Clash Meta / Mihomo**: Import the Clash subscription URL directly
- **v2rayN** (Windows): 6.x+ can import the Clash subscription; legacy versions import the VLESS universal subscription (`-vless` endpoint)
- **Shadowrocket** (iOS): Both subscription formats are supported
- **v2rayNG** (Android): Recent versions can import the Clash subscription; legacy versions import the VLESS universal subscription (`-vless` endpoint)

> **Note**:
> - The Clash subscription is **Clash Meta YAML format** — legacy v2rayN/v2rayNG cannot import it directly; use the VLESS universal subscription endpoint (with `-vless` suffix) instead
> - TLS (8443) nodes use self-signed certificates — enable **skip-cert-verify** in your client (the VLESS link already includes `allowInsecure=1`)
> - XHTTP (8880) nodes use the Reality security layer — no skip-cert-verify needed, but requires a recent mihomo/Clash Meta kernel (≥ 2024.1)
> - Reality (443) nodes require no extra settings

## System Tuning Parameters

The script intelligently calculates kernel parameters based on user-input bandwidth (interactive mode) or a default 200Mbps (unattended mode):

- **BBR congestion control** + `fq` qdisc
- **TCP buffers**: Calculated from bandwidth (formula: bandwidth × 12500 bytes, 100ms RTT), capped at 64MB, floor at 1MB
- **Connection queues**: Scale with bandwidth (≤200M: 8192 / ≤1000M: 16384 / >1000M: 32768)
- **UDP buffers**: Reuse `net.core.rmem_max` / `wmem_max` (scaled in sync with TCP buffers) to reduce UDP relay/QUIC packet loss
- **TCP Fast Open**: Enabled
- **MTU probing**: Automatic PMTU discovery
- **File descriptors**: System-level 1,048,576; service-level 131,072
- **Swap optimization**: swappiness=10, vfs_cache_pressure=50
- **Timestamps/SACK/Window scaling**: All enabled
- **Security hardening**: Source routing/redirects disabled, SYN cookies enabled

### Bandwidth Parameter Reference

| Bandwidth | TCP Buffer | Conn Queue | Use Case |
|-----------|-----------|------------|----------|
| 100 Mbps | 1 MB | 8192 | Low-spec VPS |
| 200 Mbps | 2 MB | 8192 | Standard proxy (default) |
| 500 Mbps | 6 MB | 16384 | Mid-high spec server |
| 1000 Mbps | 12 MB | 16384 | Gigabit server |
| 2000+ Mbps | 25 MB | 32768 | 10G / high concurrency |

## Dependencies

Auto-installed packages:

| Package | Purpose |
|---------|---------|
| curl | Downloads, IP lookup |
| unzip | Xray archive extraction |
| jq | JSON parsing |
| openssl | Certificate generation, random bytes |
| nginx | Subscription file HTTP server |
| haveged | Entropy daemon (optional, failure ignored) |

## Security

- **Private key permissions**: 600 when Xray runs as root; 640 + chown for non-root; auto-repairs permissions and retries on startup failure
- **Subscription endpoint**: Random 16-char hex path (16^16 search space, infeasible to brute-force), only allows specific path, others return 404; access_log disabled for privacy; HTTP by default, use only on trusted networks
- **Security headers**: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection
- **SELinux**: Auto-sets file context to prevent 403 Forbidden
- **No hardcoded secrets**: All keys/UUIDs generated randomly at deploy time
- **Clock check**: Verifies NTP sync before deployment (Reality handshake is time-sensitive)
- **Config pre-check**: jq JSON validation + `xray run -test` semantic check; aborts and rolls back on failure; Reality dest is additionally preflighted for TLS1.3 + h2 in Step 7 with automatic fallback

## Version History

### v4.5.4

- **Fixed `limit_req` detection again**: the detection temp file started with a `.`, and nginx include wildcards use libc `glob()` (`*` never matches dotfiles), so the test config was never included and the check always reported the module as available. The file no longer starts with a dot, and stale leftovers are cleaned before each write so a crashed run can't leave a file that breaks `nginx -t` forever on builds without the module.
- **Fixed original site 404 after rollback**: the `restore_nginx_default_vhosts` rollback restored vhost files but never reloaded nginx (process running, site still 404). It now does a `restart`/`start` fallback after restoring.
- **Subscription path persisted**: `SUB_PATH` (random 16-char hex) is now written to `/etc/proxy-manager.env`, so `proxy-manager info`/`sub` can still produce the full subscription URL even if the nginx config is lost.
- **`show_info` subscription recovery**: uses the persisted env `SUB_PORT`/`SUB_PATH` first (falls back to sed extraction), and adds `/etc/nginx/http.d/proxy-sub.conf` to the config lookup.
- **Fixed infinite loop on EOF**: interrupted stdin (EOF) in the custom subscription-name prompt no longer loops forever; it falls back to the default filename.
- **`proxy-manager` gained `disable`**: on non-systemd (sysvinit/OpenRC) systems the `uninstall` `disable` call was silently a no-op; it now properly removes boot auto-start.
- **Fixed false Swap warning**: an already-active `/swapfile` (listed in `/proc/swaps`) no longer reports "cannot enable" because `swapon` returns busy.
- **Uninstall fallback**: restoring default vhosts now explicitly covers `/etc/nginx/http.d/default.conf` (Alpine when env is lost).

### v4.5.3

- **Fixed interrupted deploys leaving no rollback**: Ctrl+C / SIGTERM mid-deploy now triggers a full rollback and releases the concurrency lock (added INT/TERM traps + an idempotence guard so the rollback stack never runs twice when both INT and EXIT traps fire).
- **Fixed `limit_req` detection**: `limit_req` is a default-compiled nginx module, so `nginx -V` configure args never list it and the old grep check silently disabled rate limiting on every standard build. Detection now writes a temp config and verifies with `nginx -t`.
- **Fixed misleading nginx restart failure**: When `nginx -t` passes but the service fails to restart, the script no longer misreports "config error / port in use" and deletes the config — it now reports the service error separately with journal logs.
- **Fixed uninstall deleting user drop-ins**: `/etc/systemd/system/xray.service.d` now only removes the `limits.conf` written by the script (rmdir if empty), no more `rm -rf` of the whole directory (consistent with the nginx handling).
- **Fixed Swap failure leaving disk garbage**: `swapon` failure now removes the fallocate-created file, avoiding wasted disk in container environments.
- **Removed unused dependencies**: `socat` / `wget` are never called by the script and are removed from the auto-install list.
- **Rollback noise reduction**: Early failures (e.g. concurrency lock conflict) no longer print the pointless "deployment failed, rolling back" message with an empty stack.
- **Uninstall fallback**: `proxy-manager uninstall` now explicitly removes `/etc/nginx/http.d/proxy-sub.conf`.

### v4.5.2

- **Fixed Alpine subscription endpoint failure**: Nginx config is now written to `http.d/` (Alpine) or `conf.d/` (other distros) based on the distro layout — the subscription endpoint no longer 404s on Alpine; the default-vhost disable/restore logic now also covers `http.d/default.conf`.
- **Fixed dangling-symlink cleanup dead code**: Residual dangling symlinks in `sites-enabled` are now removed correctly, preventing nginx include emerg errors that broke `nginx -t`.
- **Removed invalid sysctls**: `net.core.rmem_udp_max` / `net.core.wmem_udp_max` do not exist in the Linux kernel (they produced boot warnings and had no effect); UDP buffers now reuse `net.core.rmem_max` / `wmem_max`.
- **Nginx restart after uninstall**: `proxy-manager uninstall` now restarts nginx so default vhosts take effect again and the subscription endpoint is removed.
- **Rollback completeness**: `/etc/security/limits.d/99-proxy.conf` is now added to the rollback stack.
- **Reality dest preflight timeout fallback**: When the `timeout` command is missing, a background process + timed kill is used instead, avoiding infinite hangs on unreachable targets.
- **apt tolerance**: `apt-get update` / `upgrade` failures no longer abort deployment — they warn and continue.
- **Subscription rate limiting**: Nginx `limit_req` enabled (5r/s, burst 10); automatically skipped only on custom nginx builds lacking the limit_req module.
- **Configurable rule source**: New `RULES_CDN_PREFIX` variable — if jsdelivr is unreliable, replace it with GitHub direct or a ghproxy mirror at the top of the script before deploying.
- **Concurrency guard**: A lock file (with stale-lock cleanup) prevents multiple instances from interfering with each other.
- **Other**: IPv4-forced IP detection (`curl -4`), `proxy-manager status` now also checks the subscription port, removed unused sysctl backup logic, README version consistency.

### v4.5.1

- **Added VLESS universal subscription**: Also generates base64-encoded `vless://` links (`nodes.txt` + `<sub-path>-vless` endpoint) for clients that do not support Clash Meta YAML (v2rayN/v2rayNG/Shadowrocket legacy versions).
- **Fixed Xray install fallback**: curl download failure no longer silently succeeds — now downloads to a temp file + non-empty check, with a clear error on failure.
- **Fixed Swap fstab write timing**: `swapon` failure no longer unconditionally writes to fstab, avoiding failed-mount logs on every boot in container environments.
- **Fixed uninstall hardcoded paths**: `proxy-manager uninstall` and `rules` commands now use `$WEB_ROOT` — no more leftover files when paths differ.
- **Fixed uninstall Xray silent success**: Switched to temp-file mode + warn prompt for manual uninstall when download fails.
- **Improved `read` behavior on EOF**: Non-interactive pipe input no longer causes silent exit.
- **Improved Alpine compatibility**: Defensive `mkdir -p` before writing nginx conf.d config.
- **Improved Swap disk-space preflight**: Checks root partition free space before creation; warns if insufficient.
- **Improved Xray version observability**: Prints the actual installed version number after install.
- **Improved rollback-stack eval safety constraint**: Added comment clarifying that only hardcoded strings are allowed.
- **Doc fixes**: Subscription update interval (rolling 24h, not fixed 06:30), low-memory prompt condition (Swap < 2GB, not RAM < 1GB), v2rayN/v2rayNG subscription format notes.

### v4.5

- Removed invalid server-side fragment config; Fragment splitting now takes effect on the Clash subscription side only.
- Improved web-service handling: only stops running nginx/apache2/httpd/caddy processes and automatically restores non-conflicting services after rollback or deployment.
- Improved nginx default-vhost handling: disabling the default site now uses "symlink removal + real-file rename" to avoid dangling symlinks that break `nginx -t`; default vhosts are restored on uninstall.
- XHTTP inbound now includes `quic` / `routeOnly` sniffing settings.
- `pkill` uses `-x` exact matching to avoid accidental kills.
- Config semantic pre-check (`xray run -test`) moved after certificate generation to avoid the inevitable failure caused by missing certs.
- Subscription path generation switched to `openssl rand -hex 8` fixed-length output to avoid the `tr | head` SIGPIPE issue that silently triggered rollback.

## Troubleshooting

### Auto Rollback on Failure

If any step fails, the script automatically:
- Stops services
- Removes installed packages
- Deletes configs and certificates
- Restores original sysctl settings
- Cleans Nginx configuration

### Common Issues

**Key generation failure**
```
Ensure xray is installed correctly: xray version; xray x25519
The script has 5 fallback modes including OpenSSL generation.
```

**Nginx fails to start**
```bash
ss -tlnp | grep 10707          # Check port conflict
nginx -t                        # Test config
```

**Xray permission error**
```bash
chown nobody:nogroup /etc/xray/server.key
chmod 640 /etc/xray/server.key
proxy-manager restart
```

**Subscription URL unreachable**
```bash
proxy-manager status            # Check Nginx is running
curl -I http://127.0.0.1:10707/<path>
```

**BBR not enabled**
```bash
sysctl net.ipv4.tcp_congestion_control
uname -r  # Kernel must be >=4.9
```

### Logs

```bash
journalctl -u xray -n 50 --no-pager      # Xray logs
journalctl -u nginx -n 50 --no-pager     # Nginx logs
xray run -test -config /usr/local/etc/xray/config.json  # Config test
nginx -t                                  # Nginx config test
```

## File Paths

| File | Path |
|------|------|
| Xray config | `/usr/local/etc/xray/config.json` |
| Xray certs | `/etc/xray/server.crt` / `/etc/xray/server.key` |
| Xray binary | `/usr/local/bin/xray` |
| Clash subscription | `/usr/share/nginx/html/clash.yaml` (or `/var/www/html/`) |
| VLESS universal subscription | `/usr/share/nginx/html/nodes.txt` (raw) + `nodes_base64.txt` (base64) |
| Nginx config | `/etc/nginx/conf.d/proxy-sub.conf` (Alpine: `/etc/nginx/http.d/proxy-sub.conf`) |
| Manager CLI | `/usr/local/bin/proxy-manager` |
| Manager CLI env | `/etc/proxy-manager.env` |
| Sysctl config | `/etc/sysctl.d/99-proxy-optimized.conf` |
| Limits config | `/etc/security/limits.d/99-proxy.conf` |
| Systemd limits | `/etc/systemd/system/xray.service.d/limits.conf` |

## Uninstall

```bash
proxy-manager uninstall
```

## Disclaimer

This script is for learning and lawful use only. Users must comply with applicable laws and regulations in their jurisdiction. The author assumes no liability for misuse.

## Tech Stack

- **Core**: Xray-core (VLESS + Reality + Vision + XHTTP); Fragment splitting is applied on the Clash subscription side
- **Web Server**: Nginx
- **Config formats**: JSON (Xray), YAML (Clash Meta)
- **Encryption**: X25519 (Reality), ECC P-256 (self-signed TLS)
- **Kernel**: BBR, FQ, TCP Fast Open
