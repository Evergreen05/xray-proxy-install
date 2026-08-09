# xray-proxy-install

<div align="center">

**中文** · [English](README.en.md)

</div>

---

VLESS + Reality + Vision + Fragment 跨境电商网络代理一键部署脚本（v4.5.5），支持自动 BBR 优化、自动 Swap 配置、Clash 订阅生成、多发行版兼容。Fragment 分片仅在客户端订阅侧生效，服务端不再保留无效 fragment 配置。

[![GitHub](https://img.shields.io/badge/GitHub-Evergreen05/xray--proxy--install-blue?logo=github)](https://github.com/Evergreen05/xray-proxy-install)

## 快速开始

### 前置条件

- 拥有 **root** 权限的 Linux 服务器
- 支持的操作系统：Ubuntu 16.04+、Debian 9+、CentOS 7+、RHEL 7+、Rocky/Alma/Anolis 8+、Fedora 29+、openSUSE、Arch、Alpine（需预装 bash）
- 内核建议 4.9+（启用 BBR 拥塞控制）
- 云服务器安全组放行端口：**443**、**8443**、**8880**、**10707**
- 系统需预装 `curl` 或 `wget`（大多数系统默认已安装）

### 方式一：一键安装（推荐）

在服务器上以 root 身份执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh)
```

或使用 `wget`：

```bash
wget -qO- https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh | bash
```

### 方式二：无人值守安装（-y 参数）

跳过所有交互提示，自动选择默认选项（**不自动更新系统包**，**不配置 Swap**，网络参数使用 200Mbps 默认值）。`-y` 模式适合重复部署或 CI 场景，避免无人值守时执行全量系统升级导致意外中断。如需自定义 Swap 大小或网络参数，请使用交互模式：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh) -y
```

### 方式三：手动下载运行

如果想先审查脚本内容再执行：

```bash
# 下载
wget https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh

# （可选）审查脚本内容
# nano install.sh

# 赋予执行权限并运行
chmod +x install.sh
bash install.sh
```

> **提示**：部署完成后，执行 `proxy-manager info` 查看订阅地址和节点参数。

## 功能特性

- **多协议节点**：Reality+Vision（主力/防探测）、VLESS+TLS（备用）、XHTTP+Reality（CDN兼容）；Fragment 分片在客户端订阅配置中生效
- **单域名单端口 Reality**：默认伪装目标为 `cdn-dynmedia-1.microsoft.com:443`，一机仅暴露一个真实存在的微软动态媒体 CDN 证书，避免多端口/多公司站点被主动探测识别
- **dest 部署时自动预检**：Step 7 用 `openssl s_client -tls1_3 -alpn h2` 实测目标，不满足则剔除；全部失败时从备用池自动替补；仍失败则告警继续部署不阻断
- **DNS 优化**：Clash 端 fake-ip + fallback-filter 防污染；服务端 Xray 内置 DoH 解析
- **自动 BBR 优化**：根据用户输入的带宽（Mbps）智能计算 TCP 缓冲区和连接队列参数（100ms RTT 公式）
- **Swap 配置**：交互模式下询问是否配置及大小（MB），推荐值为物理内存 2 倍；无人值守模式跳过（容器环境创建失败不中断部署）
- **Clash 订阅**：自动生成 Clash Meta 格式订阅文件，通过 Nginx 提供 HTTP 下载端点
- **VLESS 通用订阅**：同时生成 `vless://` 链接的 base64 订阅（`nodes.txt` / `<sub-path>-vless` 端点），兼容 v2rayN/v2rayNG/Shadowrocket 旧版等不支持 Clash Meta YAML 的客户端
- **智能分流规则**：基于 [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)（⭐ ~27.6k），每日自动更新，白名单模式精确国内外分流
- **自动证书**：ECC P-256 自签名证书（SAN 覆盖全部伪装域名），安全权限设置
- **版本固定**：Xray-core 固定版本安装（v26.3.27），失败自动回退最新版
- **配置预检**：部署时 jq 验证 JSON + `xray run -test` 语义校验，不合格不启动
- **时钟检测**：部署前检查 NTP 同步状态（Reality 握手对时间敏感）
- **启动自愈**：Xray 启动失败时自动修复证书权限并重试
- **跨平台兼容**：支持 apt/dnf/yum/pacman/zypper/apk 六大包管理器（Alpine 需预先安装 bash，且未经充分测试）
- **跨服务管理**：支持 systemd/sysvinit/OpenRC 三种服务管理器
- **防火墙自动放行**：自动配置 ufw/firewalld/iptables（含规则持久化）
- **SELinux 兼容**：CentOS/RHEL/Anolis 自动设置 httpd_sys_content_t 上下文
- **失败自动回滚**：部署过程中任意步骤失败自动回滚所有变更（覆盖安装时还原旧配置）
- **管理脚本**：部署后提供 `proxy-manager` 命令管理服务（含配置测试、订阅地址查询）
- **密钥兜底**：多种 X25519 密钥提取与校验模式（含 JSON、正则、OpenSSL 本地生成等 5 种兜底），兼容不同 Xray 版本输出

## 支持的操作系统

| 发行版 | 版本要求 | 包管理器 | 服务管理器 | 备注 |
|-------|---------|---------|-----------|------|
| Ubuntu | 16.04+ | apt | systemd | |
| Debian | 9+ | apt | systemd | |
| CentOS | 7+ | yum/dnf | systemd | |
| RHEL | 7+ | yum/dnf | systemd | |
| Rocky Linux | 8+ | dnf | systemd | |
| AlmaLinux | 8+ | dnf | systemd | |
| Anolis OS（龙蜥） | 8+ | dnf | systemd | |
| Fedora | 29+ | dnf | systemd | |
| openSUSE | Leap 15+ / Tumbleweed | zypper | systemd | |
| Arch Linux / Manjaro | 滚动版 | pacman | systemd | |
| Alpine Linux | 3.12+ | apk | OpenRC | 需预装 bash，OpenRC 路径未经充分测试 |
| Amazon Linux | 2/2023 | yum/dnf | systemd | |
| openEuler（欧拉） | 20.03+ | dnf | systemd | |

> 容器环境（OpenVZ/LXC）下 Swap 创建失败不会中断部署；内核需 4.9+ 以支持 BBR。

## 重要提示

- **订阅默认走 HTTP**：部署完成后生成的订阅链接是 `http://IP:10707/随机路径`。HTTP 明文传输可能被中间人截获，建议仅在可信网络使用，或通过 SFTP/SCP 直接下载 `/usr/share/nginx/html/clash.yaml` 到本地。如需 HTTPS 必须自备域名和证书。最安全的做法是不通过公网订阅链接，直接用 SFTP/SCP 把配置文件拉到本地。
- **TLS 节点需跳过证书校验**：8443 端口使用自签名证书，客户端必须开启 `skip-cert-verify`。
- **Reality 是主力节点**：443 端口 Reality 节点无需额外设置，推荐日常使用；TLS 与 XHTTP 作为备用/兼容性节点。

## 部署流程

脚本共执行 **14 个步骤**（另有预检和结果输出）：

| 步骤 | 内容 |
|-----|------|
| 预检 | 系统检测与权限检查（必须 root） |
| 1 | 获取服务器公网 IP + NTP 时钟同步检测 |
| 2 | 内存检查与 Swap 配置（交互模式询问是否配置及大小，-y 跳过） |
| 3 | 环境检查与端口冲突检测（停止旧服务、清理残留、备份旧配置） |
| 4 | 系统更新与依赖安装 |
| 5 | 网络内核优化（BBR/TCP/文件描述符，交互模式询问带宽智能计算参数，-y 用默认值） |
| 6 | 安装 Xray-core（固定版本，失败回退最新版） |
| 7 | 生成 UUID、X25519 密钥对、Short ID、订阅路径；**预检 Reality dest（TLS1.3 + h2），失败自动从备用池替补** |
| 8 | 生成 Xray 配置文件（3 个入站：Reality + TLS + XHTTP）+ 配置预检 |
| 9 | 生成自签名 ECC 证书（SAN 覆盖伪装域名）并设置安全权限 |
| 10 | 生成 Clash 订阅配置文件（3 节点 + DNS + 分流规则）+ VLESS 通用订阅（`nodes.txt` / base64） |
| 11 | 配置 Nginx 订阅端点（Clash + VLESS 两个端点） |
| 12 | 配置 systemd 服务限制并启动服务（含证书权限自动修复） |
| 13 | 创建 `proxy-manager` 管理脚本 |
| 14 | 防火墙放行与健康检查 |
| 输出 | 打印部署结果、节点清单、订阅地址 |

## 节点配置

当前采用**单域名单端口 Reality**设计：默认伪装目标 `cdn-dynmedia-1.microsoft.com:443` 对应一个 Reality 入站，再搭配 TLS（8443）与 XHTTP（8880）两个备用入站，共 **3 个节点**。节点命名格式为 `<网络类型>-<CDN标签>`（如 `Reality-Microsoft-CDN`）。

- 若主目标预检失败并从备用池自动替补，则三个节点会共享同一个 fallback 域名（如 `Reality-Apple-Update`、`TLS-Apple-Update`、`XHTTP-Apple-Update`），仅端口不同；
- 如需扩展，往脚本头部 `REALITY_CDNS` 数组添加 `域名|端口|标签` 即可自动级联生成 Reality/TLS/XHTTP 三组节点。不同 Reality 入站必须使用不同端口，不可同时占用 443。

| 伪装 CDN | 节点标签 | Reality 端口 | dest |
|---------|---------|-------------|------|
| cdn-dynmedia-1.microsoft.com | Microsoft-CDN | 443 | cdn-dynmedia-1.microsoft.com:443 |

| 网络类型 | 端口 | 协议 | 传输 | 加密 | 用途 |
|---------|------|------|------|------|------|
| Reality | 443 | VLESS | TCP + Vision | Reality | 主力推荐，防探测；订阅配置含 Fragment 分片 |
| TLS | 8443 | VLESS | TCP + Vision | TLS（自签） | 备用节点，SNI 为 Microsoft-CDN 域名 |
| XHTTP | 8880 | VLESS | XHTTP | Reality | CDN 兼容，Reality 安全层，SNI 为 Microsoft-CDN 域名 |

- **Fragment**：TLS Client Hello 分片（100-200字节，间隔10-50ms），增强抗检测能力；由 Clash Meta 客户端在订阅侧生效，服务端 Xray 不再配置 fragment
- **Reality**：单域名单端口，探测者只能看到 443 上 Microsoft 动态媒体 CDN 的真实证书；默认 dest 支持 TLS1.3 + h2，证书链干净（Microsoft 企业 CA）
- **Vision**：XTLS Vision 流控，提供高性能代理
- **XHTTP**：基于 HTTP/2 的 XHTTP 传输 + Reality 安全层（无需自签证书），支持 CDN 中转
- **订阅分组**：Proxy → Reality / TLS / XHTTP 三个子分组，仅手动 `select`，不含 url-test 与 fallback

## Reality dest 选型与自愈

### 为什么改为单域名单端口？

旧版脚本在同一台服务器上同时伪装 Apple、Microsoft、Bing 等多家公司的 5 个站点，并开放 5 个不同端口。这在 Reality 社区共识中属于**极强的主动探测特征**：

- 同一 IP 同时“持有”多个不同公司的高价值 CDN，与真实服务器形态不符；
- 多端口 + 多域名组合容易被特征库收录；
- Bing、Apple 下载 CDN 等目标已被大量教程用滥，指纹嘈杂。

新版收敛为单域名单端口：默认 dest `cdn-dynmedia-1.microsoft.com:443`，对应真实世界中存在的微软动态媒体 CDN 服务器形态，探测者只能看到一个干净的企业级 CDN 证书。

### dest 预检与备用池

部署 Step 7 会调用 `check_reality_dest`，用 `openssl s_client -tls1_3 -alpn h2` 实测每个目标：

1. 主目标 `cdn-dynmedia-1.microsoft.com` 通过预检则直接使用；
2. 主目标失败时，按序尝试备用池：`updates.cdn-apple.com` → `iosapps.itunes.apple.com` → `download-porter.hoyoverse.com` → `osxapps.itunes.apple.com` → `music.apple.com` → `tv.apple.com` → `www.mi.com` → `buylite.music.apple.com` → `www.lamer.com.hk`；**只会采用第一个通过预检的域名**，不会同时部署多个；
3. 备用池全部失败时，脚本会告警但**继续部署不阻断**（可能是服务器出网受限，客户端侧未必不可用），并默认使用备用池第一个域名继续生成配置。

这套机制让脚本在默认域名失效时仍能自愈，无需手动修改代码。

## 分流规则

生成的 Clash 订阅使用 [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)（⭐ ~27.6k），是最受欢迎且维护最活跃的 Clash 规则集之一。

| 规则集 | 分类 | 行为 |
|-------|------|------|
| `reject` | 广告、追踪器、恶意软件 | REJECT |
| `private` | 私有/局域网 IP、内网域名 | DIRECT |
| `direct` | 中国大陆域名和 IP | DIRECT |
| `lancidr` | 局域网 CIDR 段 | DIRECT |
| `cncidr` | 中国 CIDR 段 | DIRECT |
| `proxy` | 境外/被墙域名 | Proxy |
| `apple` | Apple 服务 | Proxy |
| `google` | Google 服务 | Proxy |
| `icloud` | iCloud 服务 | Proxy |
| `telegramcidr` | Telegram IP 段 | Proxy |
| `applications` | 应用层进程规则 | DIRECT |

**核心特点：**
- 专为 **Clash Meta（mihomo）** 内核设计
- 兼容 Clash Verge Rev、mihomo Party、OpenClash（mihomo 内核）、Shadowrocket（较新版本）、Stash 等客户端；**Clash for Windows 已归档停更，不支持 Reality/XHTTP/fragment，请勿使用**
- **每 24 小时自动更新一次**（滚动间隔，自客户端首次拉取时刻起算，非固定时间点触发）
- 数据来源可靠：v2ray-rules-dat、domain-list-community、中国 IP 列表
- **白名单模式**：未匹配的流量默认走代理（MATCH=Proxy），确保所有被封锁站点正常访问

> 订阅链接默认通过 HTTP 在 `10707` 端口提供。如需 HTTPS，可在前端部署 Nginx/Caddy 配置有效证书。
>
> **规则集下载源可配置**：默认使用 jsdelivr CDN。国内网络拉取规则失败时，可编辑 `install.sh` 头部的 `RULES_CDN_PREFIX` 变量，改为 GitHub 直连（`https://raw.githubusercontent.com/Loyalsoldier/clash-rules@release`）或 ghproxy 镜像后重新部署。

## DNS 优化

### 客户端（Clash Meta / mihomo）

- **fake-ip 模式**（198.18.0.1/16）：加速连接建立，避免 DNS 污染导致连错 IP
- **fake-ip-filter**：Windows NCSI 检测域名（msftconnecttest.com）和 Apple 服务域名始终获取真实 IP，避免 TUN 模式关闭后 Windows 误报“无法访问 Internet”
- **国内 nameserver**：223.5.5.5 / 119.29.29.29 / 114.114.114.114（纯 UDP，解析快）
- **fallback**：`1.1.1.1` / `8.8.8.8`（明文 UDP）
- **fallback-filter**：GeoIP CN + geosite:gfw + 240.0.0.0/4 + 指定域名（google/facebook/youtube），被墙域名强制走 fallback 防污染
- **respect-rules**：DNS 查询同样遵循分流规则。`1.1.1.1`/`8.8.8.8` 不命中 cncidr/GEOIP,CN → 落到规则链末尾的 `MATCH,Proxy` → DNS 查询经代理隧道发出，明文 UDP 被隧道加密保护，无需 DoH 二次加密（省一次 TLS 握手，且无 `dns.google` 解析依赖）。**隐患：此方案依赖 `MATCH,Proxy` 兜底，切勿将 `1.1.1.1`/`8.8.8.8` 加入 DIRECT/IP-CIDR 规则，否则 DNS 查询将明文直连被 GFW 投毒。若改规则后无法保证，请改回 DoH 更稳妥。**
- **proxy-server-nameserver**：代理节点域名解析走国内 DNS，避免死循环

### 服务端（Xray）

- Xray 内置 DNS：`https://1.1.1.1/dns-query` + `https://dns.google/dns-query`（DoH）
- freedom 出站 `domainStrategy: UseIPv4`，避免 VPS 系统 DNS 异常或 IPv6 回退问题

## 部署后管理

部署完成后使用 `proxy-manager` 命令管理服务：

```bash
proxy-manager info       # 查看服务器信息、订阅地址、节点参数
proxy-manager sub        # 仅输出订阅地址（方便复制）
proxy-manager status     # 查看 Xray 和 Nginx 运行状态、端口监听
proxy-manager test       # 测试 Xray 与 Nginx 配置是否合法
proxy-manager start      # 启动所有服务
proxy-manager stop       # 停止所有服务
proxy-manager restart    # 重启所有服务
proxy-manager config     # 查看 Xray 配置（JSON 格式化输出）
proxy-manager rules      # 查看 Clash 规则文件路径
proxy-manager log        # 查看 Xray 最近 50 行日志
proxy-manager uninstall  # 完全卸载代理服务（含配置文件和证书）
```

## 端口要求

部署前请确保以下端口未被占用，并在云服务器控制台安全组放行：

| 端口 | 协议 | 用途 |
|-----|------|------|
| 443 | TCP | Reality 主力节点 - Microsoft-CDN（cdn-dynmedia-1.microsoft.com） |
| 8443 | TCP | VLESS TLS 备用节点（自签证书） |
| 8880 | TCP | VLESS XHTTP CDN 兼容节点（Reality 安全层） |
| 10707 | TCP | Clash 订阅 HTTP 端点（可修改） |

## 客户端配置

本脚本同时生成两种订阅格式，按客户端类型选择：

### 订阅端点

| 端点 | 格式 | 适用客户端 |
|------|------|-----------|
| `http://IP:10707/<sub-path>` | Clash Meta YAML | Clash Meta / Mihomo / v2rayN 6.x+ |
| `http://IP:10707/<sub-path>-vless` | VLESS base64 通用订阅 | v2rayN/v2rayNG/Shadowrocket 旧版等 |

### 推荐客户端

- **Clash Meta / Mihomo**：直接导入 Clash 订阅链接
- **v2rayN**（Windows）：6.x+ 可导入 Clash 订阅；旧版导入 VLESS 通用订阅（`-vless` 端点）
- **Shadowrocket**（iOS）：两种订阅均支持
- **v2rayNG**（Android）：较新版本可导入 Clash 订阅；旧版导入 VLESS 通用订阅（`-vless` 端点）

> **注意**：
> - Clash 订阅为 **Clash Meta YAML 格式**，旧版 v2rayN/v2rayNG 无法直接导入，请用 VLESS 通用订阅端点（`-vless` 后缀）
> - TLS（8443）组节点使用自签名证书，客户端需启用 **skip-cert-verify**（VLESS 链接中已带 `allowInsecure=1`）
> - XHTTP（8880）组使用 Reality 安全层，无需 skip-cert-verify，但需较新版本 mihomo/Clash Meta 内核（≥ 2024.1）
> - Reality（443）组无需额外设置

## 系统优化参数

脚本根据用户输入的带宽（交互模式）或默认 200Mbps（无人值守模式）智能计算内核参数：

- **BBR 拥塞控制** + `fq` 队列调度
- **TCP 缓冲区**：根据带宽智能计算（公式：带宽 × 12500 字节，100ms RTT），上限 64MB，下限 1MB
- **连接队列**：随带宽缩放（≤200M: 8192 / ≤1000M: 16384 / >1000M: 32768）
- **UDP 缓冲区**：复用 `net.core.rmem_max` / `wmem_max`（随 TCP 同步放大），减少 UDP 中继/QUIC 丢包
- **TCP Fast Open**：启用 TFO
- **MTU 探测**：自动 PMTU 发现
- **文件描述符**：系统级 1048576，服务级 131072
- **Swap 优化**：swappiness=10，vfs_cache_pressure=50
- **时间戳/SACK/窗口缩放**：全部启用
- **安全加固**：禁用源路由、重定向，启用 SYN Cookie

### 带宽参数对照表

| 带宽 | TCP 缓冲区 | 连接队列 | 适用场景 |
|------|-----------|---------|----------|
| 100 Mbps | 1 MB | 8192 | 低配 VPS |
| 200 Mbps | 2 MB | 8192 | 常规代理（默认） |
| 500 Mbps | 6 MB | 16384 | 中高配服务器 |
| 1000 Mbps | 12 MB | 16384 | 千兆服务器 |
| 2000+ Mbps | 25 MB | 32768 | 万兆/高并发 |

## 安装依赖

脚本自动安装以下依赖包：

| 包 | 用途 |
|---|------|
| curl | 文件下载、IP 获取 |
| unzip | Xray 压缩包解压 |
| jq | JSON 解析（配置管理） |
| openssl | 证书生成、随机数 |
| nginx | 订阅文件 HTTP 服务 |
| haveged | 随机数生成（可选，失败不中断） |

## 安全说明

- **私钥权限**：当 Xray 以 root 运行时私钥权限 `600`，非 root 用户时 `640` + `chown`；启动失败自动修复权限并重试
- **订阅端点**：随机 16 字符十六进制路径（取值空间 16^16，暴力穷举不可行），仅允许访问指定路径，其他路径返回 404；订阅端点关闭 access_log 保护隐私；默认 HTTP，建议仅在可信网络使用
- **安全响应头**：Nginx 添加 `X-Content-Type-Options`、`X-Frame-Options`、`X-XSS-Protection`
- **SELinux**：自动设置文件上下文，避免 403 Forbidden
- **无硬编码密码/密钥**：所有密钥和 UUID 在部署时随机生成
- **时钟校验**：部署前检测 NTP 同步（Reality 握手对时间敏感）
- **配置预检**：jq 验证 JSON 合法性 + `xray run -test` 语义校验，不合格中止部署并回滚；Reality dest 在 Step 7 额外进行 TLS1.3 + h2 预检并自动替补

## 版本更新说明

### v4.5.5

- **Clash 分流严格对齐官方规则**：rule-providers 补齐 `gfw` / `tld-not-cn` 两个规则集，与 Loyalsoldier/clash-rules 官方 README 的 13 个 provider 完全一致；`icloud` / `apple` 域名由走代理改回官方默认的 `DIRECT`；rules 条目与顺序保持与官方白名单模式逐条一致（官方示例中的 `PROXY` 策略对应本配置的 `Proxy` 分组）。

### v4.5.4

- **修复 `limit_req` 检测失效**：检测用临时配置文件名以 `.` 开头，而 nginx include 走 libc `glob()`（`*` 不匹配 dot 文件），测试文件永不生效导致检测恒为可用；改为非点文件名并在写入前清理历史残留，未编译该模块的自定义构建上不再误报；
- **修复回滚后原站点 404**：回滚时 `restore_nginx_default_vhosts` 恢复 vhost 文件后 nginx 未重载（进程在跑但站点 404），恢复后补一次 `restart/start` 兜底；
- **订阅路径持久化**：`SUB_PATH`（随机 16 位 hex）现在写入 `/etc/proxy-manager.env`，nginx 配置丢失后 `proxy-manager info/sub` 仍能恢复完整订阅地址；
- **`show_info` 订阅信息恢复**：优先使用 env 持久化的 `SUB_PORT`/`SUB_PATH`（缺失时退回 sed 提取），并补充 `/etc/nginx/http.d/proxy-sub.conf` 查找兜底；
- **修复自定义订阅名 EOF 死循环**：stdin 输入中断（EOF）时不再无限循环提示，自动回退默认文件名；
- **proxy-manager 补 `disable` 分支**：非 systemd（sysvinit/OpenRC）系统上 `uninstall` 的 `disable` 调用此前静默无效，现可正确移除开机自启；
- **修复 Swap 已激活误报**：`/swapfile` 已在 `/proc/swaps` 中激活时不再因 `swapon` 报 busy 而误报"无法启用"；
- **卸载兜底**：`proxy-manager uninstall` 恢复默认 vhost 时显式覆盖 `/etc/nginx/http.d/default.conf`（env 丢失的 Alpine 场景）。

### v4.5.3

- **修复中断无回滚**：部署中途 Ctrl+C / SIGTERM 中断现在会触发完整回滚并释放并发锁（新增 INT/TERM trap + 幂等保护，防止 EXIT/INT 双触发重复回滚）；
- **修复 `limit_req` 检测失效**：`limit_req` 是 nginx 默认编译模块，`nginx -V` 的 configure 参数不包含模块名，原 grep 检测恒不命中导致限速静默失效；改为写入临时配置 + `nginx -t` 实测检测；
- **修复 nginx 重启失败误报**：`nginx -t` 通过但服务重启失败时，不再误报"配置错误/端口占用"并删除配置，改为单独提示服务错误并输出日志；
- **修复 uninstall 误删用户配置**：`/etc/systemd/system/xray.service.d` 改为只删除脚本写入的 `limits.conf` 再 rmdir，不再 `rm -rf` 整个目录（与 nginx 处理一致）；
- **修复 Swap 失败残留磁盘文件**：`swapon` 启用失败时删除 fallocate 创建的文件，避免容器环境白占磁盘；
- **移除未使用的依赖**：`socat` / `wget` 脚本内零调用，从自动安装列表移除；
- **回滚噪音优化**：并发锁冲突等早期失败不再打印空转的"部署失败，开始回滚"提示；
- **卸载兜底**：`proxy-manager uninstall` 增加 `/etc/nginx/http.d/proxy-sub.conf` 显式清理。

### v4.5.2

- **修复 Alpine 订阅端点失效**：Nginx 配置按发行版写入 `http.d/`（Alpine）或 `conf.d/`（其他发行版），Alpine 上订阅端点不再 404；默认 vhost 禁用/恢复逻辑同步覆盖 `http.d/default.conf`；
- **修复悬空符号链接清理死代码**：`sites-enabled` 中残留的悬空链接现在会被正确删除，避免 nginx include 报 emerg 导致 `nginx -t` 失败；
- **移除无效 sysctl**：`net.core.rmem_udp_max` / `net.core.wmem_udp_max` 在 Linux 内核中不存在（会产生开机告警且不生效），UDP 缓冲复用 `net.core.rmem_max` / `wmem_max`；
- **卸载后重启 Nginx**：`proxy-manager uninstall` 现在会重启 nginx，使默认 vhost 恢复生效、订阅端点移除；
- **回滚补齐**：`/etc/security/limits.d/99-proxy.conf` 加入回滚栈；
- **Reality dest 预检超时兜底**：`timeout` 命令缺失时改用后台进程 + 定时 kill，避免对不可达目标无限挂起；
- **apt 源更新容错**：`apt-get update` / `upgrade` 失败不再直接中止部署，改为告警后继续；
- **订阅端点限速**：Nginx 启用 `limit_req`（5r/s，burst 10），未编译该模块的自定义 nginx 构建自动跳过；
- **分流规则源可配置**：新增 `RULES_CDN_PREFIX` 变量，jsdelivr 不可用时可在脚本头部替换为 GitHub 直连或 ghproxy 镜像；
- **并发保护**：新增锁文件（含陈旧锁清理），防止多个实例同时运行互相干扰；
- **其他**：IP 检测强制 IPv4（`curl -4`）、`proxy-manager status` 增加订阅端口检查、移除无用 sysctl 备份逻辑、README 版本号统一。

### v4.5.1

- **新增 VLESS 通用订阅**：同时生成 `vless://` 链接的 base64 订阅（`nodes.txt` + `<sub-path>-vless` 端点），兼容 v2rayN/v2rayNG/Shadowrocket 旧版等不支持 Clash Meta YAML 的客户端；
- **修复 Xray 安装回退机制**：curl 下载失败时不再静默成功，改为下载到临时文件 + 非空校验，失败时清晰报错；
- **修复 Swap fstab 写入时机**：`swapon` 失败后不再无条件写 fstab，避免容器环境每次开机产生失败挂载日志；
- **修复 uninstall 硬编码路径**：`proxy-manager uninstall` 和 `rules` 命令改用 `$WEB_ROOT`，路径不一致时不再残留文件；
- **修复 uninstall Xray 卸载静默成功**：改为临时文件模式 + 下载失败时 warn 提示手动卸载；
- **改进 `read` 在 EOF 下的行为**：非交互管道输入时不再静默退出；
- **改进 Alpine 兼容性**：nginx conf.d 目录写配置前防御性 `mkdir -p`；
- **改进 Swap 磁盘空间预检**：创建前检查根分区剩余空间，不足时 warn；
- **改进 Xray 版本可观测性**：安装后打印实际版本号；
- **改进回滚栈 eval 安全约束**：添加注释明确仅限硬编码字符串；
- **修正文档**：订阅更新间隔描述（滚动 24h 而非固定 06:30）、低内存提示条件（Swap < 2GB 而非 RAM < 1GB）、v2rayN/v2rayNG 订阅格式说明。

### v4.5

- 移除服务端无效 fragment 配置，Fragment 分片改在 Clash 订阅侧生效；
- 优化 Web 服务处理：仅停止运行中的 nginx/apache2/httpd/caddy，并在回滚或部署完成后自动恢复非冲突服务；
- 改进 nginx 默认 vhost 处理：禁用默认站点时采用“符号链接删除 + 真实文件重命名”，避免残留悬空链接导致 `nginx -t` 失败；卸载时自动恢复默认 vhost；
- XHTTP inbound 补齐 `quic` / `routeOnly` 等 sniffing 配置；
- `pkill` 使用 `-x` 精确匹配，防止误杀其他进程；
- 配置语义预检（`xray run -test`）调整至证书生成之后，避免证书尚未生成时预检必然失败；
- 订阅路径生成改用 `openssl rand -hex 8` 定长输出，避免 `tr | head` 管道被 SIGPIPE 截断导致静默回滚。

## 故障排查

### 部署失败自动回滚

任意步骤失败后，脚本自动回滚已执行的变更：
- 停止服务
- 删除安装的软件包
- 删除配置文件和证书
- 恢复原始 sysctl 配置
- 清理 Nginx 配置

### 常见问题

**密钥生成失败**
```
确保 xray 正确安装：xray version；xray x25519
脚本内置 5 种兜底模式，包括 OpenSSL 本地生成。
```

**Nginx 启动失败**
```bash
ss -tlnp | grep 10707          # 检查端口冲突
nginx -t                        # 测试配置
```

**Xray 权限错误**
```bash
chown nobody:nogroup /etc/xray/server.key
chmod 640 /etc/xray/server.key
proxy-manager restart
```

**无法访问订阅链接**
```bash
proxy-manager status            # 检查 Nginx 是否运行
curl -I http://127.0.0.1:10707/<path>
```

**BBR 未启用**
```bash
sysctl net.ipv4.tcp_congestion_control
uname -r  # 内核需 ≥4.9
```

### 日志查看

```bash
journalctl -u xray -n 50 --no-pager      # Xray 日志
journalctl -u nginx -n 50 --no-pager     # Nginx 日志
xray run -test -config /usr/local/etc/xray/config.json  # 配置测试
nginx -t                                  # Nginx 配置测试
```

## 文件路径

| 文件 | 路径 |
|-----|------|
| Xray 配置 | `/usr/local/etc/xray/config.json` |
| Xray 证书 | `/etc/xray/server.crt` / `/etc/xray/server.key` |
| Xray 程序 | `/usr/local/bin/xray` |
| Clash 订阅文件 | `/usr/share/nginx/html/clash.yaml`（或 `/var/www/html/`） |
| VLESS 通用订阅 | `/usr/share/nginx/html/nodes.txt`（原始）+ `nodes_base64.txt`（base64） |
| Nginx 配置 | `/etc/nginx/conf.d/proxy-sub.conf`（Alpine 为 `/etc/nginx/http.d/proxy-sub.conf`） |
| 管理脚本 | `/usr/local/bin/proxy-manager` |
| 管理脚本参数 | `/etc/proxy-manager.env` |
| 系统优化配置 | `/etc/sysctl.d/99-proxy-optimized.conf` |
| 文件描述符配置 | `/etc/security/limits.d/99-proxy.conf` |
| systemd 限制 | `/etc/systemd/system/xray.service.d/limits.conf` |

## 卸载

```bash
proxy-manager uninstall
```

## 免责声明

本脚本仅供学习和合法用途。使用本脚本部署代理服务需遵守所在国家/地区的法律法规，用户需自行承担使用风险。

## 技术栈

- **核心**：Xray-core（VLESS + Reality + Vision + XHTTP）；Fragment 分片在 Clash 订阅侧生效
- **Web 服务**：Nginx
- **配置格式**：JSON（Xray）、YAML（Clash Meta）
- **加密**：X25519（Reality）、ECC P-256（自签 TLS）
- **内核优化**：BBR、FQ、TCP Fast Open
