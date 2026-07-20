# xray-proxy-install

<div align="center">

**中文** · [English](README.en.md)

</div>

---

VLESS + Reality + Vision + Fragment 跨境电商网络代理一键部署脚本，支持自动 BBR 优化、自动 Swap 配置、Clash 订阅生成、多发行版兼容。

[![GitHub](https://img.shields.io/badge/GitHub-Evergreen05/xray--proxy--install-blue?logo=github)](https://github.com/Evergreen05/xray-proxy-install)

## 功能特性

- **多协议节点**：Reality+Vision+Fragment（主力/防探测）、VLESS+TLS（备用）、XHTTP+TLS（CDN兼容）
- **自动 BBR 优化**：根据内存动态计算 TCP 缓冲区参数
- **自动 Swap 配置**：低内存服务器（<1GB）自动配置 2GB 虚拟内存
- **Clash 订阅**：自动生成 Clash Meta 格式订阅文件，通过 Nginx 提供 HTTP 下载端点
- **智能分流规则**：基于 [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)（⭐ ~27.6k），每日自动更新，白名单模式精确国内外分流
- **自动证书**：ECC P-256 自签名证书生成，安全权限设置
- **跨平台兼容**：支持 apt/dnf/yum/pacman/zypper/apk 六大包管理器
- **跨服务管理**：支持 systemd/sysvinit/OpenRC 三种服务管理器
- **防火墙自动放行**：自动配置 ufw/firewalld/iptables
- **SELinux 兼容**：CentOS/RHEL/Anolis 自动设置 httpd_sys_content_t 上下文
- **失败自动回滚**：部署过程中任意步骤失败自动回滚所有变更
- **管理脚本**：部署后提供 `proxy-manager` 命令管理服务
- **密钥兜底**：5种 X25519 密钥提取模式，含 OpenSSL 本地生成兜底

## 支持的操作系统

| 发行版 | 版本要求 | 包管理器 | 服务管理器 |
|-------|---------|---------|-----------|
| Ubuntu | 16.04+ | apt | systemd |
| Debian | 9+ | apt | systemd |
| CentOS | 7+ | yum/dnf | systemd |
| RHEL | 7+ | yum/dnf | systemd |
| Rocky Linux | 8+ | dnf | systemd |
| AlmaLinux | 8+ | dnf | systemd |
| Anolis OS（龙蜥） | 8+ | dnf | systemd |
| Fedora | 29+ | dnf | systemd |
| openSUSE | Leap 15+ / Tumbleweed | zypper | systemd |
| Arch Linux / Manjaro | 滚动版 | pacman | systemd |
| Alpine Linux | 3.12+ | apk | OpenRC |
| Amazon Linux | 2/2023 | yum/dnf | systemd |
| openEuler（欧拉） | 20.03+ | dnf | systemd |

> 容器环境（OpenVZ/LXC）下 Swap 创建失败不会中断部署；内核需 4.9+ 以支持 BBR。

## 快速开始

### 前置条件

- 拥有 **root** 权限的 Linux 服务器
- 支持的操作系统：Ubuntu 16.04+、Debian 9+、CentOS 7+、RHEL 7+、Rocky/Alma/Anolis 8+、Fedora 29+、openSUSE、Arch、Alpine
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

跳过所有交互提示，自动选择默认选项（自动更新系统、内存不足时配置 Swap）：

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

## 部署流程

脚本共执行 16 个步骤：

| 步骤 | 内容 |
|-----|------|
| 1 | 系统检测与权限检查（必须 root） |
| 2 | 端口冲突检测与公网 IP 获取 |
| 3 | 内存检查与 Swap 配置 |
| 4 | 环境清理（停止旧服务、删除残留配置） |
| 5 | 系统更新与依赖安装 |
| 6 | 网络内核优化（BBR/TCP/文件描述符） |
| 7 | 安装 Xray-core |
| 8 | 生成 UUID、X25519 密钥对、Short ID |
| 9 | 生成 Xray 配置文件（3 个入站节点） |
| 10 | 生成自签名 ECC 证书并设置安全权限 |
| 11 | 生成 Clash 订阅配置文件 |
| 12 | 配置 Nginx 订阅端点 |
| 13 | 配置 systemd 服务限制并启动服务 |
| 14 | 创建 `proxy-manager` 管理脚本 |
| 15 | 防火墙放行与健康检查 |
| 16 | 输出部署结果 |

## 节点配置

| 节点 | 端口 | 协议 | 传输 | 加密 | 用途 |
|-----|------|------|------|------|------|
| 节点1 | 443 | VLESS | TCP + Vision | Reality | 主力推荐，防 GFW 探测，Fragment 分片 |
| 节点2 | 8443 | VLESS | TCP + Vision | TLS（自签） | 备用节点 |
| 节点3 | 8880 | VLESS | XHTTP | TLS（自签） | CDN 兼容 |

- **Fragment**：TLS Client Hello 分片（100-200字节，间隔10-50ms），增强抗检测能力
- **Reality**：使用 `swdist.apple.com` 作为伪装目标，无需真实域名和证书
- **Vision**：XTLS Vision 流控，提供高性能代理
- **XHTTP**：基于 HTTP/2 的 XHTTP 传输，支持 CDN 中转

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
- 专为 **Clash Premium** / **Clash Meta（mihomo）** 内核设计
- 兼容 ClashX Pro、Clash for Windows、Clash Verge Rev、OpenClash、Shadowrocket 等客户端
- **每日自动更新**（北京时间 06:30，配置为 24 小时间隔）
- 数据来源可靠：v2ray-rules-dat、domain-list-community、中国 IP 列表
- **白名单模式**：未匹配的流量默认走代理（MATCH=Proxy），确保所有被封锁站点正常访问

> 订阅链接默认通过 HTTP 在 `10707` 端口提供。如需 HTTPS，可在前端部署 Nginx/Caddy 配置有效证书。

## 部署后管理

部署完成后使用 `proxy-manager` 命令管理服务：

```bash
proxy-manager info       # 查看服务器信息、订阅地址、节点参数
proxy-manager status     # 查看 Xray 和 Nginx 运行状态、端口监听
proxy-manager start      # 启动所有服务
proxy-manager stop       # 停止所有服务
proxy-manager restart    # 重启所有服务
proxy-manager config     # 查看 Xray 配置（JSON 格式化输出）
proxy-manager rules      # 查看 Clash 规则文件路径
proxy-manager log        # 查看 Xray 最近 50 行日志
proxy-manager uninstall  # 完全卸载代理服务（含配置文件和证书）
proxy-manager help       # 查看帮助信息
```

## 端口要求

部署前请确保以下端口未被占用，并在云服务器控制台安全组放行：

| 端口 | 协议 | 用途 |
|-----|------|------|
| 443 | TCP | VLESS Reality 主节点 |
| 8443 | TCP | VLESS TLS 备用节点 |
| 8880 | TCP | VLESS XHTTP CDN 节点 |
| 10707 | TCP | Clash 订阅 HTTP 端点（可修改） |

## 客户端配置

推荐客户端：

- **Clash Meta / Mihomo**：直接导入订阅链接
- **v2rayN**（Windows）：手动添加 VLESS 节点或导入订阅
- **Shadowrocket**（iOS）：支持 Clash 订阅和 VLESS
- **v2rayNG**（Android）：支持 VLESS 和订阅导入

> **注意**：节点2（8443）和节点3（8880）使用自签名证书，客户端需启用 **skip-cert-verify**（跳过证书验证）。

## 系统优化参数

脚本自动配置以下内核参数：

- **BBR 拥塞控制** + `fq` 队列调度
- **TCP 缓冲区**：动态计算，4MB 上限（平衡内存与性能）
- **TCP Fast Open**：启用 TFO
- **MTU 探测**：自动 PMTU 发现
- **文件描述符**：系统级 1048576，服务级 131072
- **连接队列**：somaxconn=8192，tcp_max_syn_backlog=8192
- **Swap 优化**：swappiness=10，vfs_cache_pressure=50
- **时间戳/SACK/窗口缩放**：全部启用
- **安全加固**：禁用源路由、重定向，启用 SYN Cookie、RFC 1337 防护

## 安装依赖

脚本自动安装以下依赖包：

| 包 | 用途 |
|---|------|
| curl / wget | 文件下载 |
| unzip | Xray 压缩包解压 |
| socat | 网络工具（端口检测） |
| jq | JSON 解析（配置管理） |
| openssl | 证书生成、随机数 |
| nginx | 订阅文件 HTTP 服务 |
| haveged | 随机数生成（可选，失败不中断） |

## 安全说明

- **私钥权限**：当 Xray 以 root 运行时私钥权限 `600`，非 root 用户时 `640` + `chown`
- **订阅端点**：随机 16 字符路径，仅允许访问指定路径，其他路径返回 404
- **安全响应头**：Nginx 添加 `X-Content-Type-Options`、`X-Frame-Options`、`X-XSS-Protection`
- **SELinux**：自动设置文件上下文，避免 403 Forbidden
- **无硬编码密码/密钥**：所有密钥和 UUID 在部署时随机生成

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
| Nginx 配置 | `/etc/nginx/conf.d/proxy-sub.conf` |
| 管理脚本 | `/usr/local/bin/proxy-manager` |
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

- **核心**：Xray-core（VLESS + Reality + Vision + XHTTP + Fragment）
- **Web 服务**：Nginx
- **配置格式**：JSON（Xray）、YAML（Clash Meta）
- **加密**：X25519（Reality）、ECC P-256（自签 TLS）
- **内核优化**：BBR、FQ、TCP Fast Open
