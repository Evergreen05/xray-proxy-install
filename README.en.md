# xray-proxy-install

<div align="center">

[中文](README.md) · **English**

</div>

---

VLESS + Reality + Vision + Fragment proxy one-click installer for cross-border e-commerce networks. BBR optimization, auto Swap, Clash subscription, multi-distro support.

[![GitHub](https://img.shields.io/badge/GitHub-Evergreen05/xray--proxy--install-blue?logo=github)](https://github.com/Evergreen05/xray-proxy-install)

## Features

- **Multi-protocol nodes**: Reality+Vision+Fragment (primary/anti-detection), VLESS+TLS (backup), XHTTP+Reality (CDN-compatible)
- **Single-domain, single-port Reality**: Default fronting target is `cdn-dynmedia-1.microsoft.com:443`. The server only exposes one real Microsoft dynamic media CDN certificate on 443, avoiding the strong active-probing signature of multi-port/multi-site setups
- **Dest preflight at deploy time**: Step 7 uses `openssl s_client -tls1_3 -alpn h2` to verify the target. Failing domains are dropped; if all fail, the script auto-falls back through the backup pool. If the pool also fails, it warns and continues without blocking deployment
- **DNS optimization**: Client-side fake-ip + fallback-filter anti-pollution; server-side Xray built-in DoH resolution
- **Auto BBR optimization**: Dynamic TCP buffer calculation based on available memory
- **Auto Swap**: Automatically configures 2GB Swap on low-memory servers (<1GB)
- **Clash subscription**: Auto-generates Clash Meta format subscription via Nginx HTTP endpoint
- **Smart routing rules**: Powered by [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) (⭐ ~27.6k), auto-updated daily, whitelist mode with precise geo-routing
- **Auto certificates**: ECC P-256 self-signed certs (SAN covers all camouflage domains) with secure permission handling
- **Pinned version**: Xray-core installed at a fixed version (v26.3.27), auto-fallback to latest on failure
- **Config pre-check**: jq JSON validation + `xray run -test` semantic check before starting services
- **Clock detection**: Checks NTP sync before deployment (Reality handshake is time-sensitive)
- **Self-healing start**: Auto-repairs certificate permissions and retries if Xray fails to start
- **Cross-platform**: Supports apt/dnf/yum/pacman/zypper/apk (6 package managers)
- **Cross-init**: Supports systemd/sysvinit/OpenRC (3 service managers)
- **Auto firewall**: Configures ufw/firewalld/iptables automatically (with rule persistence)
- **SELinux compatible**: Auto-sets httpd_sys_content_t on CentOS/RHEL/Anolis
- **Auto rollback**: Any failure triggers automatic rollback of all changes (restores previous config on overwrite installs)
- **Management CLI**: `proxy-manager` command for post-deploy administration (includes config test & subscription URL query)
- **Key fallback**: 5-mode X25519 key extraction with OpenSSL fallback

## Supported Operating Systems

| Distro | Version | Package Mgr | Init System |
|--------|---------|-------------|-------------|
| Ubuntu | 16.04+ | apt | systemd |
| Debian | 9+ | apt | systemd |
| CentOS | 7+ | yum/dnf | systemd |
| RHEL | 7+ | yum/dnf | systemd |
| Rocky Linux | 8+ | dnf | systemd |
| AlmaLinux | 8+ | dnf | systemd |
| Anolis OS (龙蜥) | 8+ | dnf | systemd |
| Fedora | 29+ | dnf | systemd |
| openSUSE | Leap 15+ / Tumbleweed | zypper | systemd |
| Arch Linux / Manjaro | Rolling | pacman | systemd |
| Alpine Linux | 3.12+ | apk | OpenRC |
| Amazon Linux | 2/2023 | yum/dnf | systemd |
| openEuler (欧拉) | 20.03+ | dnf | systemd |

> Container environments (OpenVZ/LXC): Swap creation failure will not abort deployment. Kernel 4.9+ required for BBR.

## Quick Start

### Prerequisites

- A Linux server with **root** access
- Supported OS: Ubuntu 16.04+, Debian 9+, CentOS 7+, RHEL 7+, Rocky/Alma/Anolis 8+, Fedora 29+, openSUSE, Arch, Alpine
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

Skips all interactive prompts (auto-updates system, configures Swap if needed):

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

## Installation Process

The script runs through **14 steps** (plus a pre-check and final output):

| Step | Description |
|------|-------------|
| Pre | Root privilege check & distro detection |
| 1 | Acquire public IP + NTP clock sync check |
| 2 | Memory check & Swap configuration |
| 3 | Environment check & port conflict detection (stop old services, cleanup, backup old config) |
| 4 | System update & dependency installation |
| 5 | Network kernel optimization (BBR/TCP/Files) |
| 6 | Install Xray-core (pinned version, fallback to latest) |
| 7 | Generate UUID, X25519 keypair, Short ID, subscription path; **preflight Reality dest (TLS1.3 + h2), auto-fallback to backup pool on failure** |
| 8 | Generate Xray config (3 inbounds: Reality + TLS + XHTTP) + config pre-check |
| 9 | Generate self-signed ECC certificates (SAN covers camouflage domains) with secure permissions |
| 10 | Generate Clash subscription config (3 nodes + DNS + routing rules) |
| 11 | Configure Nginx subscription endpoint |
| 12 | Configure systemd limits & start services (with auto cert-permission repair) |
| 13 | Create `proxy-manager` CLI tool |
| 14 | Firewall rules & health checks |
| Output | Print deployment results, node list, subscription URL |

## Node Configuration

This release uses a **single-domain, single-port Reality** design: the default fronting target `cdn-dynmedia-1.microsoft.com:443` maps to one Reality inbound, plus TLS (8443) and XHTTP (8880) backup inbounds — **3 nodes** in total. Node names follow `<Type>-<CDN-Label>` (e.g. `Reality-Microsoft-CDN`). To scale, append `domain|port|label` entries to the `REALITY_CDNS` array at the top of the script; the Reality/TLS/XHTTP groups will cascade automatically.

| Camouflage CDN | Node Label | Reality Port | dest |
|----------------|-----------|--------------|------|
| cdn-dynmedia-1.microsoft.com | Microsoft-CDN | 443 | cdn-dynmedia-1.microsoft.com:443 |

| Type | Port | Protocol | Transport | Encryption | Purpose |
|------|------|----------|-----------|------------|---------|
| Reality | 443 | VLESS | TCP + Vision | Reality | Primary, anti-detection, Fragment |
| TLS | 8443 | VLESS | TCP + Vision | TLS (self-signed) | Backup, SNI = Microsoft-CDN domain |
| XHTTP | 8880 | VLESS | XHTTP | Reality | CDN compatible, Reality security layer, SNI = Microsoft-CDN domain |

- **Fragment**: TLS Client Hello fragmentation (100-200 bytes, 10-50ms interval) for enhanced anti-detection
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
2. If it fails, the script tries the fallback pool in order: `updates.cdn-apple.com`, `iosapps.itunes.apple.com`, `download-porter.hoyoverse.com`, `osxapps.itunes.apple.com`, `music.apple.com`, `tv.apple.com`, `www.mi.com`, `buylite.music.apple.com`, `www.lamer.com.hk`;
3. If the fallback pool also fails, the script warns but **continues deployment without blocking** (the server’s outbound may be restricted while the client side might still work).

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
- Designed for **Clash Premium** / **Clash Meta (mihomo)** kernel
- Compatible with ClashX Pro, Clash for Windows, Clash Verge Rev, OpenClash, Shadowrocket, etc.
- **Auto-updated daily** at 06:30 Beijing time (24h interval configured)
- Reliable data sources: v2ray-rules-dat, domain-list-community, China IP list
- **Whitelist mode**: unmatched traffic defaults to proxy (MATCH=Proxy), ensuring all blocked sites go through the proxy

> The subscription URL is served over HTTP on port `10707` by default. For HTTPS, you can put Nginx/Caddy behind with a valid certificate.

## DNS Optimization

### Client-side (Clash Meta / mihomo)

- **fake-ip mode** (198.18.0.1/16): Faster connection setup; avoids connecting to poisoned IPs
- **Domestic nameservers**: 223.5.5.5 / 119.29.29.29 / 114.114.114.114 (plain UDP, fast resolution)
- **Fallback**: 1.1.1.1 / 8.8.8.8 (foreign DNS)
- **fallback-filter**: GeoIP CN + geosite:gfw + 240.0.0.0/4 + specified domains (google/facebook/youtube) — blocked domains forced to fallback
- **respect-rules**: DNS queries follow the same routing rules as traffic
- **proxy-server-nameserver**: Proxy node domain resolution uses domestic DNS to avoid loops

### Server-side (Xray)

- Xray built-in DNS: `https://1.1.1.1/dns-query` + `https://dns.google/dns-query` + 8.8.8.8
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

Recommended clients:

- **Clash Meta / Mihomo**: Import subscription URL directly
- **v2rayN** (Windows): Add VLESS nodes manually or import subscription
- **Shadowrocket** (iOS): Supports Clash subscription and VLESS
- **v2rayNG** (Android): Supports VLESS and subscription import

> **Note**:
> - TLS (8443) nodes use self-signed certificates — enable **skip-cert-verify** in your client
> - XHTTP (8880) nodes use the Reality security layer — no skip-cert-verify needed, but requires a recent mihomo/Clash Meta kernel (≥ 2024.1)
> - Reality (443) nodes require no extra settings

## System Tuning Parameters

The script auto-configures:

- **BBR congestion control** + `fq` qdisc
- **TCP buffers**: Dynamically calculated, 4MB max (balanced for memory and performance)
- **TCP Fast Open**: Enabled
- **MTU probing**: Automatic PMTU discovery
- **File descriptors**: System-level 1,048,576; service-level 131,072
- **Connection queues**: somaxconn=8192, tcp_max_syn_backlog=8192
- **Swap optimization**: swappiness=10, vfs_cache_pressure=50
- **Timestamps/SACK/Window scaling**: All enabled
- **Security hardening**: Source routing/redirects disabled, SYN cookies enabled

## Dependencies

Auto-installed packages:

| Package | Purpose |
|---------|---------|
| curl / wget | Downloads |
| unzip | Xray archive extraction |
| socat | Network utilities |
| jq | JSON parsing |
| openssl | Certificate generation, random bytes |
| nginx | Subscription file HTTP server |
| haveged | Entropy daemon (optional, failure ignored) |

## Security

- **Private key permissions**: 600 when Xray runs as root; 640 + chown for non-root; auto-repairs permissions and retries on startup failure
- **Subscription endpoint**: Random 16-char hex path, only allows specific path, others return 404; access_log disabled for privacy
- **Security headers**: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection
- **SELinux**: Auto-sets file context to prevent 403 Forbidden
- **No hardcoded secrets**: All keys/UUIDs generated randomly at deploy time
- **Clock check**: Verifies NTP sync before deployment (Reality handshake is time-sensitive)
- **Config pre-check**: jq JSON validation + `xray run -test` semantic check; aborts and rolls back on failure; Reality dest is additionally preflighted for TLS1.3 + h2 in Step 7 with automatic fallback

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
| Nginx config | `/etc/nginx/conf.d/proxy-sub.conf` |
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

- **Core**: Xray-core (VLESS + Reality + Vision + XHTTP + Fragment)
- **Web Server**: Nginx
- **Config formats**: JSON (Xray), YAML (Clash Meta)
- **Encryption**: X25519 (Reality), ECC P-256 (self-signed TLS)
- **Kernel**: BBR, FQ, TCP Fast Open
