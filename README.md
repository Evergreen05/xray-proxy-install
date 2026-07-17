# xray-proxy-install

VLESS + Reality + Vision + Fragment proxy one-click installer for cross-border e-commerce networks. BBR optimization, auto Swap, Clash subscription, multi-distro support.

[![GitHub](https://img.shields.io/badge/GitHub-Evergreen05/xray--proxy--install-blue?logo=github)](https://github.com/Evergreen05/xray-proxy-install)

## Features

- **Multi-protocol nodes**: Reality+Vision+Fragment (primary/anti-detection), VLESS+TLS (backup), XHTTP+TLS (CDN-compatible)
- **Auto BBR optimization**: Dynamic TCP buffer calculation based on available memory
- **Auto Swap**: Automatically configures 2GB Swap on low-memory servers (<1GB)
- **Clash subscription**: Auto-generates Clash Meta format subscription via Nginx HTTP endpoint
- **Smart routing rules**: Powered by [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) (~27.6k stars), auto-updated daily with precise geo-routing
- **Auto certificates**: ECC P-256 self-signed certs with secure permission handling
- **Cross-platform**: Supports apt/dnf/yum/pacman/zypper/apk (6 package managers)
- **Cross-init**: Supports systemd/sysvinit/OpenRC (3 service managers)
- **Auto firewall**: Configures ufw/firewalld/iptables automatically
- **SELinux compatible**: Auto-sets httpd_sys_content_t on CentOS/RHEL/Anolis
- **Auto rollback**: Any failure triggers automatic rollback of all changes
- **Management CLI**: `proxy-manager` command for post-deploy administration
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

### One-Click Install (Interactive)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh)
```

### Unattended Install (-y flag)

Skips all interactive prompts, uses defaults:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh) -y
```

### Manual Download

```bash
wget https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh
chmod +x install.sh
bash install.sh
```

## Installation Process

The script runs through 16 steps:

| Step | Description |
|------|-------------|
| 1 | Root privilege check & distro detection |
| 2 | Port conflict detection & public IP acquisition |
| 3 | Memory check & Swap configuration |
| 4 | Environment cleanup (stop old services, remove stale configs) |
| 5 | System update & dependency installation |
| 6 | Network kernel optimization (BBR/TCP/Files) |
| 7 | Install Xray-core |
| 8 | Generate UUID, X25519 keypair, Short ID |
| 9 | Generate Xray config (3 inbound nodes) |
| 10 | Generate self-signed ECC certificates with secure permissions |
| 11 | Generate Clash subscription config |
| 12 | Configure Nginx subscription endpoint |
| 13 | Configure systemd limits & start services |
| 14 | Create `proxy-manager` CLI tool |
| 15 | Firewall rules & health checks |
| 16 | Output deployment results |



## Node Configuration

| Node | Port | Protocol | Transport | Encryption | Purpose |
|------|------|----------|-----------|------------|---------|
| Node 1 | 443 | VLESS | TCP + Vision | Reality | Primary, anti-GFW detection, Fragment |
| Node 2 | 8443 | VLESS | TCP + Vision | TLS (self-signed) | Backup |
| Node 3 | 8880 | VLESS | XHTTP | TLS (self-signed) | CDN compatible |

- **Fragment**: TLS Client Hello fragmentation (100-200 bytes, 10-50ms interval) for enhanced anti-detection
- **Reality**: Uses `swdist.apple.com` as impersonation target, no real domain/cert required
- **Vision**: XTLS Vision flow control for high performance
- **XHTTP**: HTTP/2-based XHTTP transport, supports CDN relay

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
| `gfw` | GFW-list domains | Proxy |
| `tld-not-cn` | Non-Chinese TLDs | Proxy |
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

## Post-Deployment Management

After deployment, use the `proxy-manager` command:

```bash
proxy-manager info       # Server info, subscription URL, node parameters
proxy-manager status     # Xray & Nginx service status, port monitoring
proxy-manager start      # Start all services
proxy-manager stop       # Stop all services
proxy-manager restart    # Restart all services
proxy-manager config     # View Xray config (JSON formatted)
proxy-manager rules      # View Clash rules file path
proxy-manager log        # View last 50 lines of Xray logs
proxy-manager uninstall  # Completely uninstall (configs, certs, rules)
proxy-manager help       # Show help
```

## Required Ports

Ensure these ports are open in your cloud security group/firewall before deployment:

| Port | Protocol | Purpose |
|------|----------|---------|
| 443 | TCP | VLESS Reality primary node |
| 8443 | TCP | VLESS TLS backup node |
| 8880 | TCP | VLESS XHTTP CDN node |
| 10707 | TCP | Clash subscription HTTP endpoint (configurable) |

## Client Setup

Recommended clients:

- **Clash Meta / Mihomo**: Import subscription URL directly
- **v2rayN** (Windows): Add VLESS nodes manually or import subscription
- **Shadowrocket** (iOS): Supports Clash subscription and VLESS
- **v2rayNG** (Android): Supports VLESS and subscription import

> **Note**: Node 2 (8443) and Node 3 (8880) use self-signed certificates. Enable **skip-cert-verify** in your client.

## System Tuning Parameters

The script auto-configures:

- **BBR congestion control** + `fq` qdisc
- **TCP buffers**: Dynamically calculated, 8MB max (optimized for 1GB RAM)
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

- **Private key permissions**: 600 when Xray runs as root; 640 + chown for non-root
- **Subscription endpoint**: Random 16-character path, only allows specific path, others return 404
- **Security headers**: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection
- **SELinux**: Auto-sets file context to prevent 403 Forbidden
- **No hardcoded secrets**: All keys/UUIDs generated randomly at deploy time

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
