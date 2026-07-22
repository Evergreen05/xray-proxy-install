#!/bin/bash
set -e -o pipefail
# 统一命令输出语言，保证解析（密钥/IP等）不受系统语言影响
export LC_ALL=C

# ============================================
# Xray Proxy Install Script v4.3
# Protocol: VLESS + Reality + Vision + Fragment
# Multi-CDN: 5 个伪装域名 x Reality/TLS/XHTTP 三种网络类型 = 15 节点
# 订阅分组: Proxy -> Reality / TLS / XHTTP 三组，每组 5 个 CDN 节点
# Optimization: BBR / TCP / Subscription endpoint / Auto Swap / DNS
# Compatibility: apt/dnf/yum 已验证; pacman/zypper/apk 理论支持（未经充分测试，官方 Xray 安装器依赖 systemd）
# GitHub: https://github.com/Evergreen05/xray-proxy-install
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 非交互模式支持
AUTO_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help)
            echo "用法: bash install.sh [-y|--yes] [-h|--help]"
            echo "  -y, --yes   无人值守模式（自动确认所有提示）"
            echo "  -h, --help  显示帮助"
            exit 0
            ;;
    esac
done

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# 进度提示
STEP_TOTAL=14
STEP_CURRENT=0
step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    echo ""
    echo -e "${CYAN}[$STEP_CURRENT/$STEP_TOTAL] $1${NC}"
}

# ============================================
# 回滚机制
# ============================================
ROLLBACK_LOG=()
DEPLOY_SUCCESS=0

rollback() {
    if [ "$DEPLOY_SUCCESS" -eq 1 ]; then
        return
    fi
    echo ""
    echo -e "${RED}[ERROR]${NC} 部署失败，开始回滚..."
    for step in "${ROLLBACK_LOG[@]}"; do
        eval "$step" 2>/dev/null || true
    done
    echo -e "${YELLOW}回滚完成，请检查错误日志${NC}"
    exit 1
}

trap rollback EXIT

add_rollback() {
    ROLLBACK_LOG=("$1" "${ROLLBACK_LOG[@]}")
}

# ============================================
# 部署参数（单一事实源：端口/域名/节点名全部由此派生）
# 格式: 域名|Reality端口|节点标签
# 每个 CDN 域名 x Reality/TLS/XHTTP 三种网络类型各生成一个节点
# ============================================
REALITY_CDNS=(
    "swdist.apple.com|443|Apple-SWDIST"
    "iosapps.itunes.apple.com|1443|Apple-iTunes"
    "updates.cdn-apple.com|2443|Apple-Update"
    "cdn-dynmedia-1.microsoft.com|3443|Microsoft-CDN"
    "www.bing.com|4443|Bing"
)

# 固定 Xray 版本，避免上游输出格式变化导致部署不可复现；失败时自动回退到最新版
XRAY_VERSION="v26.3.27"
XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

# 代理端口列表（Reality 端口按 REALITY_CDNS 顺序派生 + TLS 8443 + XHTTP 8880）
PROXY_PORTS=()
REALITY_PORTS=()
for entry in "${REALITY_CDNS[@]}"; do
    _rest="${entry#*|}"
    PROXY_PORTS+=("${_rest%%|*}")
    REALITY_PORTS+=("${_rest%%|*}")
done
PROXY_PORTS+=(8443 8880)

# 节点标签列表（供 proxy-manager 动态生成节点清单）
CDN_LABELS=""
for entry in "${REALITY_CDNS[@]}"; do
    CDN_LABELS+="${entry##*|} "
done
CDN_LABELS="${CDN_LABELS% }"

# 订阅端点
SUB_PORT=10707

# ============================================
# 跨平台支持函数
# ============================================
detect_distro() {
    DISTRO_ID="unknown"
    DISTRO_LIKE="unknown"
    PKG_MANAGER="unknown"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID,,}"
        DISTRO_LIKE="${ID_LIKE,,}"
    elif [ -f /etc/redhat-release ]; then
        DISTRO_ID="rhel"
        DISTRO_LIKE="rhel"
    elif [ -f /etc/arch-release ]; then
        DISTRO_ID="arch"
        DISTRO_LIKE="arch"
    elif [ -f /etc/alpine-release ]; then
        DISTRO_ID="alpine"
        DISTRO_LIKE="alpine"
    fi

    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
    fi

    log "系统: ${DISTRO_ID} | 包管理器: ${PKG_MANAGER}"
}

system_update() {
    case "$PKG_MANAGER" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            if [ "$1" = "upgrade" ]; then
                apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
            fi
            ;;
        dnf)
            if [ "$1" = "upgrade" ]; then
                dnf upgrade -y -q
            else
                dnf makecache -q 2>/dev/null || true
            fi
            ;;
        yum)
            if [ "$1" = "upgrade" ]; then
                yum update -y -q
            else
                yum makecache -q 2>/dev/null || true
            fi
            ;;
        pacman)
            if [ "$1" = "upgrade" ]; then
                pacman -Syu --noconfirm
            else
                pacman -Sy --noconfirm
            fi
            ;;
        zypper)
            zypper refresh -q 2>/dev/null || true
            if [ "$1" = "upgrade" ]; then
                zypper update -y -n
            fi
            ;;
        apk)
            apk update 2>/dev/null || true
            if [ "$1" = "upgrade" ]; then
                apk upgrade --no-cache
            fi
            ;;
        *)
            error "不支持的包管理器: ${PKG_MANAGER}"
            ;;
    esac
}

install_packages() {
    local pkgs=("$@")
    case "$PKG_MANAGER" in
        apt)    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${pkgs[@]}" ;;
        dnf)    dnf install -y -q "${pkgs[@]}" ;;
        yum)    yum install -y -q "${pkgs[@]}" ;;
        pacman) pacman -S --noconfirm --needed "${pkgs[@]}" ;;
        zypper) zypper install -y -n "${pkgs[@]}" ;;
        apk)    apk add --no-cache "${pkgs[@]}" ;;
        *)      error "不支持的包管理器: ${PKG_MANAGER}" ;;
    esac
}

service_manage() {
    local action=$1
    local service=$2
    if command -v systemctl &>/dev/null; then
        systemctl "$action" "$service"
    elif command -v service &>/dev/null; then
        case "$action" in
            enable)  update-rc.d "$service" defaults 2>/dev/null || chkconfig "$service" on 2>/dev/null || true ;;
            start)   service "$service" start ;;
            stop)    service "$service" stop ;;
            restart) service "$service" restart ;;
            status)  service "$service" status ;;
        esac
    elif command -v rc-service &>/dev/null; then
        case "$action" in
            enable)  rc-update add "$service" default 2>/dev/null || true ;;
            start)   rc-service "$service" start ;;
            stop)    rc-service "$service" stop ;;
            restart) rc-service "$service" restart ;;
            status)  rc-service "$service" status ;;
        esac
    else
        error "未找到服务管理器"
    fi
}

is_service_active() {
    if command -v systemctl &>/dev/null; then
        systemctl is-active --quiet "$1"
    elif command -v rc-service &>/dev/null; then
        rc-service "$1" status &>/dev/null
    else
        pgrep -x "$1" &>/dev/null
    fi
}

check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -q ":${port} "
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} "
    else
        false
    fi
}

# 提取 IP 地址（不使用 grep -P）
extract_ip() {
    # grep 无匹配时返回 1，pipefail 下会使赋值失败触发 set -e 静默退出，需 || true 兜底
    echo "$1" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
}

# ============================================
# 0. 系统检测与权限检查（预检）
# ============================================
[[ $EUID -ne 0 ]] && error "请使用 root 权限运行此脚本"
detect_distro

# ============================================
# 1. 获取服务器公网 IP
# ============================================
step "获取服务器公网 IP"

# IP 获取（多源容错，不使用 grep -P）
SERVER_IP=""
for src in ifconfig.me ipinfo.io/ip ip.sb icanhazip.com; do
    RESP=$(curl -s --connect-timeout 5 --max-time 10 "https://${src}" 2>/dev/null || true)
    SERVER_IP=$(extract_ip "$RESP")
    [ -n "$SERVER_IP" ] && break
done
[ -z "$SERVER_IP" ] && error "无法获取服务器公网 IP"
log "服务器 IP: ${SERVER_IP}"

# Reality 握手校验时间戳，系统时钟必须准确
if command -v timedatectl &>/dev/null; then
    if ! timedatectl status 2>/dev/null | grep -qE "System clock synchronized: yes|NTP enabled: yes"; then
        warn "系统时钟未同步（Reality 对时间敏感），建议执行: timedatectl set-ntp true"
    fi
fi

# ============================================
# 2. 内存检查与 Swap 配置
# ============================================
step "内存检查与 Swap 配置"

TOTAL_RAM_MB=$(awk '/MemTotal/ {printf "%d", ($2+512)/1024}' /proc/meminfo)
TOTAL_SWAP_MB=$(awk '/SwapTotal/ {printf "%d", ($2+512)/1024}' /proc/meminfo)

echo ""
echo -e "${CYAN}========== 内存检查 ==========${NC}"
echo -e "${GREEN}物理内存:${NC}  ${TOTAL_RAM_MB} MB"
echo -e "${GREEN}Swap 大小:${NC} ${TOTAL_SWAP_MB} MB"
echo ""

if [ "$TOTAL_SWAP_MB" -ge 2048 ]; then
    log "Swap 大小符合要求 (${TOTAL_SWAP_MB} MB >= 2048 MB)"
else
    warn "Swap 大小不足 (${TOTAL_SWAP_MB} MB < 2048 MB)，低内存服务器建议配置 2GB Swap"
    echo ""
    echo -e "${YELLOW}是否配置 2GB Swap 虚拟内存？${NC}"
    echo -e "  ${GREEN}y${NC} - 配置（推荐 1G 内存服务器）"
    echo -e "  ${GREEN}n${NC} - 跳过（已有足够内存）"
    if [ "$AUTO_YES" -eq 1 ]; then
        CONFIG_SWAP="y"
    else
        read -p "请选择 [y/n]: " CONFIG_SWAP
        CONFIG_SWAP=${CONFIG_SWAP:-n}
    fi

    if [[ "$CONFIG_SWAP" == "y" || "$CONFIG_SWAP" == "Y" ]]; then
        log "开始配置 2GB Swap..."
        SWAP_OK=0

        if [ -f /swapfile ]; then
            warn "检测到已存在 /swapfile"
            SWAP_SIZE=$(ls -lh /swapfile | awk '{print $5}')
            echo -e "当前大小: ${SWAP_SIZE}"
            if [ "$AUTO_YES" -eq 1 ]; then
                RECREATE_SWAP="n"
            else
                echo -e "${YELLOW}是否重新创建？(y/n)${NC}"
                read -p "请选择: " RECREATE_SWAP
                RECREATE_SWAP=${RECREATE_SWAP:-n}
            fi
            if [[ "$RECREATE_SWAP" != "y" && "$RECREATE_SWAP" != "Y" ]]; then
                log "保留现有 Swap"
                if swapon /swapfile 2>/dev/null; then
                    SWAP_OK=1
                else
                    warn "现有 Swap 无法启用（容器环境可能不支持）"
                fi
                TOTAL_SWAP_MB=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
                log "当前 Swap: ${TOTAL_SWAP_MB} MB"
            else
                swapoff /swapfile 2>/dev/null || true
                rm -f /swapfile
                fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
                chmod 600 /swapfile
                mkswap /swapfile
                if swapon /swapfile 2>/dev/null; then
                    SWAP_OK=1
                else
                    SWAP_OK=0
                    warn "Swap 启用失败（容器环境可能不支持），将继续部署"
                fi
                if ! grep -q '/swapfile' /etc/fstab; then
                    echo '/swapfile none swap sw 0 0' >> /etc/fstab
                fi
                [ "$SWAP_OK" -eq 1 ] && log "2GB Swap 创建成功"
            fi
        else
            log "创建 2GB Swap 文件..."
            fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
            chmod 600 /swapfile
            mkswap /swapfile
            if swapon /swapfile 2>/dev/null; then
                SWAP_OK=1
            else
                SWAP_OK=0
                warn "Swap 启用失败（容器环境可能不支持），将继续部署"
            fi
            if ! grep -q '/swapfile' /etc/fstab; then
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
            fi
            [ "$SWAP_OK" -eq 1 ] && log "2GB Swap 创建成功"
        fi

        TOTAL_SWAP_MB=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
        echo ""
        echo -e "${GREEN}内存配置完成:${NC}"
        echo -e "  物理内存: ${TOTAL_RAM_MB} MB"
        echo -e "  Swap 大小: ${TOTAL_SWAP_MB} MB"
        echo -e "  总可用: $((TOTAL_RAM_MB + TOTAL_SWAP_MB)) MB"
    else
        warn "已跳过 Swap 配置，低内存环境下可能影响性能"
    fi
fi

# ============================================
# 3. 环境检查与端口冲突检测
# ============================================
step "环境检查与端口冲突检测"

# 覆盖安装检测：备份旧配置，回滚时还原而不是卸载用户原有环境
XRAY_PREINSTALLED=0
PREV_CONFIG_BACKUP=""
if command -v xray &>/dev/null && [ -f /usr/local/etc/xray/config.json ]; then
    XRAY_PREINSTALLED=1
    warn "检测到已安装 Xray，将进行覆盖安装（原配置已备份，部署失败时自动还原）"
    PREV_CONFIG_BACKUP="/usr/local/etc/xray/config.json.prevbak"
    cp -f /usr/local/etc/xray/config.json "$PREV_CONFIG_BACKUP" 2>/dev/null || PREV_CONFIG_BACKUP=""
    [ -f /etc/xray/server.crt ] && cp -f /etc/xray/server.crt /etc/xray/server.crt.prevbak 2>/dev/null || true
    [ -f /etc/xray/server.key ] && cp -f /etc/xray/server.key /etc/xray/server.key.prevbak 2>/dev/null || true
    service_manage stop xray 2>/dev/null || true
    sleep 1
    # 精确匹配进程名，避免误杀命令行中包含 xray 的无关进程
    pkill -x xray 2>/dev/null || true
fi

for _svc in nginx apache2 httpd caddy; do
    if command -v "$_svc" &>/dev/null; then
        service_manage stop "$_svc" 2>/dev/null || true
    fi
done
sleep 1
# 精确匹配进程名（pkill -f 宽匹配可能误杀无关进程）
pkill -x nginx 2>/dev/null || true
pkill -x apache2 2>/dev/null || true
pkill -x httpd 2>/dev/null || true

# 清理本脚本生成的旧 Nginx 配置残留
rm -f /etc/nginx/sites-enabled/proxy-sub-secure 2>/dev/null || true
rm -f /etc/nginx/sites-available/proxy-sub-secure 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/proxy-sub 2>/dev/null || true
rm -f /etc/nginx/conf.d/proxy-sub.conf 2>/dev/null || true
if [ -d /etc/nginx/sites-enabled ]; then
    for link in /etc/nginx/sites-enabled/*; do
        [ -e "$link" ] || continue
        [ -L "$link" ] && [ ! -e "$link" ] && rm -f "$link"
    done
fi

# 端口冲突检测（放在清理旧服务之后，避免重复部署时对自己的服务误报）
PORT_CONFLICT=0
for port in "${PROXY_PORTS[@]}" "$SUB_PORT"; do
    if check_port "$port"; then
        warn "端口 ${port} 已被占用"
        PORT_CONFLICT=1
    fi
done

if [ "$PORT_CONFLICT" -eq 1 ] && [ "$AUTO_YES" -eq 0 ]; then
    echo -e "${YELLOW}检测到端口冲突，是否继续？${NC}"
    read -p "请选择 [y/n]: " CONTINUE
    CONTINUE=${CONTINUE:-n}
    [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]] && error "部署已取消"
fi

# ============================================
# 4. 系统更新与依赖安装
# ============================================
step "系统更新与依赖安装"

UPDATE_SYSTEM="y"
if [ "$AUTO_YES" -eq 0 ]; then
    echo -e "${CYAN}是否更新系统包？${NC}"
    echo -e "  ${GREEN}y${NC} - 更新（推荐首次部署）"
    echo -e "  ${GREEN}n${NC} - 跳过（已部署过的服务器）"
    read -p "请选择 [y/n]: " UPDATE_SYSTEM
    UPDATE_SYSTEM=${UPDATE_SYSTEM:-y}
fi

if [[ "$UPDATE_SYSTEM" == "y" || "$UPDATE_SYSTEM" == "Y" ]]; then
    log "更新系统包..."
    system_update "upgrade"
else
    log "跳过系统更新"
    system_update "refresh"
fi

log "安装依赖..."
case "$PKG_MANAGER" in
    apt)    ESSENTIALS=(curl wget unzip socat jq openssl nginx); OPTIONAL=(haveged) ;;
    dnf|yum)
        [[ "$DISTRO_ID" =~ ^(centos|rhel|almalinux|rocky|anolis|alinux|openEuler|euleros|virtuozzo|ol)$ ]] && $PKG_MANAGER install -y -q epel-release 2>/dev/null || true
        ESSENTIALS=(curl wget unzip socat jq openssl nginx); OPTIONAL=(haveged) ;;
    *)      ESSENTIALS=(curl wget unzip socat jq openssl nginx); OPTIONAL=(haveged) ;;
esac
install_packages "${ESSENTIALS[@]}"
# 可选包：安装失败不中断部署
for pkg in "${OPTIONAL[@]}"; do
    install_packages "$pkg" 2>/dev/null || warn "可选包 ${pkg} 安装失败，跳过（不影响核心功能）"
done

# ============================================
# 5. 网络内核优化
# ============================================
step "网络内核优化"

# 根据内存动态计算 tcp_mem（单位：页，1页=4KB）
# low=物理内存*25%, pressure=50%, high=75%
TCP_MEM_LOW=$(( TOTAL_RAM_MB * 256 / 4 ))
TCP_MEM_PRESSURE=$(( TOTAL_RAM_MB * 512 / 4 ))
TCP_MEM_HIGH=$(( TOTAL_RAM_MB * 768 / 4 ))

# 备份原始配置（每次部署生成时间戳备份，仅保留最近 3 份，避免无限累积）
cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%s) 2>/dev/null || true
( ls -1t /etc/sysctl.conf.bak.* 2>/dev/null || true ) | tail -n +4 | xargs -r rm -f 2>/dev/null || true
add_rollback "rm -f /etc/sysctl.d/99-proxy-optimized.conf; sysctl --system >/dev/null 2>&1 || true"

cat > /etc/sysctl.d/99-proxy-optimized.conf << 'SYSCTL'
# ============================================
# 网络内核优化 (适配 200M 带宽)
# ============================================

# --- BBR 拥塞控制 ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# --- TCP 缓冲区 (4MB，平衡内存与性能) ---
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.ipv4.tcp_rmem=4096 87380 4194304
net.ipv4.tcp_wmem=4096 65536 4194304
net.ipv4.tcp_mem=__TCP_MEM_DYNAMIC__

# --- TCP Fast Open ---
net.ipv4.tcp_fastopen=3

# --- MTU 探测 ---
net.ipv4.tcp_mtu_probing=1

# --- 低延迟 ---
net.ipv4.tcp_notsent_lowat=16384

# --- 连接复用 ---
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_max_tw_buckets=5000

# --- Keepalive (代理场景缩短到 5 分钟) ---
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5

# --- 窗口优化 ---
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1

# --- 连接队列 ---
net.core.netdev_max_backlog=8192
net.core.somaxconn=8192
net.ipv4.tcp_max_orphans=8192
net.ipv4.tcp_max_syn_backlog=8192

# --- SYN flood 防护 ---
net.ipv4.tcp_syncookies=1

# --- 本地端口范围扩大 ---
net.ipv4.ip_local_port_range=1024 65535

# --- 禁用空闲后慢启动 ---
net.ipv4.tcp_slow_start_after_idle=0

# --- 文件描述符上限 ---
fs.file-max=1048576

# --- 安全加固 ---
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1

# --- Swap 优化 ---
vm.swappiness=10
vm.vfs_cache_pressure=50
SYSCTL

# 替换 tcp_mem 为动态计算值
sed -i "s/__TCP_MEM_DYNAMIC__/${TCP_MEM_LOW} ${TCP_MEM_PRESSURE} ${TCP_MEM_HIGH}/" /etc/sysctl.d/99-proxy-optimized.conf

sysctl --system >/dev/null 2>&1 || true

# 配置文件描述符限制（注意：仅对 PAM 登录会话生效，systemd 服务通过 override 配置）
log "配置文件描述符限制..."
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-proxy.conf << 'LIMITS'
# 代理服务器文件描述符限制 (1G内存适配)
# 注意: systemd 服务的限制通过 /etc/systemd/system/*.service.d/limits.conf 配置
* soft nofile 131072
* hard nofile 131072
root soft nofile 131072
root hard nofile 131072
* soft nproc 32768
* hard nproc 32768
root soft nproc 32768
root hard nproc 32768
LIMITS

log "网络优化完成"

# ============================================
# 6. 安装 Xray-core
# ============================================
step "安装 Xray-core"
# 优先安装固定版本（可复现）；失败时回退到最新版
if ! bash -c "$(curl -fsSL "$XRAY_INSTALL_URL")" @ install --version "${XRAY_VERSION}"; then
    warn "指定版本 ${XRAY_VERSION} 安装失败，回退到最新版本..."
    bash -c "$(curl -fsSL "$XRAY_INSTALL_URL")" @ install || error "Xray 安装失败，请检查网络或手动安装"
fi
command -v xray &>/dev/null || error "Xray 安装失败，请检查网络或手动安装"
# 回滚策略：覆盖安装时还原旧配置；全新安装时才卸载
if [ "$XRAY_PREINSTALLED" -eq 1 ]; then
    if [ -n "$PREV_CONFIG_BACKUP" ]; then
        add_rollback "cp -f '$PREV_CONFIG_BACKUP' /usr/local/etc/xray/config.json 2>/dev/null || true; rm -f '$PREV_CONFIG_BACKUP'; [ -f /etc/xray/server.crt.prevbak ] && mv -f /etc/xray/server.crt.prevbak /etc/xray/server.crt; [ -f /etc/xray/server.key.prevbak ] && mv -f /etc/xray/server.key.prevbak /etc/xray/server.key; service_manage restart xray 2>/dev/null || true"
    else
        add_rollback "service_manage restart xray 2>/dev/null || true"
    fi
else
    add_rollback "bash -c \"\$(curl -fsSL ${XRAY_INSTALL_URL})\" @ remove 2>/dev/null || true"
fi

# Xray 安装脚本会自动启动服务，先停止它，等待我们生成配置后再启动
service_manage stop xray 2>/dev/null || true
sleep 1
# 兜底：确保没有残留的 xray 进程占用端口
pkill -f "/usr/local/bin/xray" 2>/dev/null || true
sleep 1

# ============================================
# 7. 生成配置参数
# ============================================
step "生成配置参数"
UUID=$(xray uuid 2>/dev/null || true)
# 兜底：内核随机源 / openssl 生成 UUID
if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
fi
if [ -z "$UUID" ]; then
    UUID=$(openssl rand -hex 16 2>/dev/null | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/' || true)
fi
[ -z "$UUID" ] && error "UUID 生成失败，请检查 xray 是否正确安装"

# 生成 X25519 密钥对（兼容多种 Xray 版本输出格式）
PRIVATE_KEY=""
PUBLIC_KEY=""
KEYS=$(xray x25519 2>&1 || true)

# 模式1: "Private key: xxx" / "PrivateKey: xxx" / "私钥: xxx"
# 注意：$(...) 内管道必须以 || true 收尾，否则 grep 无匹配(返回 1) 在
# set -e + pipefail 下会导致脚本无任何报错静默退出并触发回滚
if [ -z "$PRIVATE_KEY" ]; then
    PRIVATE_KEY=$(echo "$KEYS" | grep -iE '(private|私钥).*(key|密钥)' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r' | tr -d '[:space:]' | head -1 || true)
fi
if [ -z "$PUBLIC_KEY" ]; then
    PUBLIC_KEY=$(echo "$KEYS" | grep -iE '(public|公钥).*(key|密钥)' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r' | tr -d '[:space:]' | head -1 || true)
fi

# 模式2: JSON 输出 {"privateKey":"xxx","publicKey":"xxx"}
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    JSON_KEYS=$(echo "$KEYS" | grep -oE '\{[^}]*"privateKey"[^}]*\}' || true)
    if [ -n "$JSON_KEYS" ] && command -v jq &>/dev/null; then
        PRIVATE_KEY=$(echo "$JSON_KEYS" | jq -r '.privateKey // empty' 2>/dev/null || true)
        PUBLIC_KEY=$(echo "$JSON_KEYS" | jq -r '.publicKey // empty' 2>/dev/null || true)
    fi
fi

# 模式3: 逐行解析，找看起来像 base64 密钥的字符串（43-44字符，base64字符集）
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    # Xray 密钥为 base64url 编码，字符集必须包含 - 和 _
    B64_KEYS=$(echo "$KEYS" | grep -oE '[A-Za-z0-9+/_-]{42,45}={0,2}' | head -2 || true)
    if [ -n "$B64_KEYS" ]; then
        KEY_COUNT=$(echo "$B64_KEYS" | wc -l)
        if [ "$KEY_COUNT" -ge 2 ]; then
            PRIVATE_KEY=$(echo "$B64_KEYS" | sed -n '1p')
            PUBLIC_KEY=$(echo "$B64_KEYS" | sed -n '2p')
        fi
    fi
fi

# 模式4: 使用 openssl 作为最后兜底生成 x25519 密钥
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    warn "xray x25519 提取失败，尝试 openssl 生成密钥..."
    if command -v openssl &>/dev/null; then
        # OpenSSL 1.1.1+ 支持 x25519；DER 格式中最后 32 字节是密钥原始值（RFC 8410）
        # 注意：Xray 使用 base64url 无填充格式，需去掉 '=' 并将 '+/' 转为 '-_'
        TMP_PRIV_DER=$(openssl genpkey -algorithm x25519 -outform DER 2>/dev/null | base64 | tr -d '\n' || true)
        if [ -n "$TMP_PRIV_DER" ]; then
            PRIVATE_KEY=$(echo "$TMP_PRIV_DER" | base64 -d 2>/dev/null | tail -c 32 | base64 | tr -d '\n=' | tr '+/' '-_' || true)
            PUBLIC_KEY=$(echo "$TMP_PRIV_DER" | base64 -d 2>/dev/null | openssl pkey -pubout -inform DER -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n=' | tr '+/' '-_' || true)
        fi
        # 如果 openssl x25519 不支持，尝试直接解析 xray 纯文本输出（无 key: 标签格式）
        if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
            PRIVATE_KEY=$(echo "$KEYS" | grep -v '^$' | grep -v '^[[:space:]]*#' | head -1 | tr -d '\r' | tr -d '[:space:]' || true)
            PUBLIC_KEY=$(echo "$KEYS" | grep -v '^$' | grep -v '^[[:space:]]*#' | sed -n '2p' | tr -d '\r' | tr -d '[:space:]' || true)
        fi
    fi
fi

# 模式5: 验证密钥有效性（X25519 密钥为 32 字节原始值，base64 编码后长度 43-44 字符）
if [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ]; then
    PRIV_LEN=${#PRIVATE_KEY}
    PUB_LEN=${#PUBLIC_KEY}
    if [ "$PRIV_LEN" -lt 43 ] || [ "$PRIV_LEN" -gt 44 ] || [ "$PUB_LEN" -lt 43 ] || [ "$PUB_LEN" -gt 44 ]; then
        warn "提取的密钥长度异常 (priv=${PRIV_LEN}, pub=${PUB_LEN})，继续尝试其他方法..."
        PRIVATE_KEY=""
        PUBLIC_KEY=""
    fi
fi

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    warn "xray x25519 原始输出:"
    echo "$KEYS"
    error "密钥生成失败，请确认 xray 版本支持 x25519（xray version 查看版本）"
fi

SHORT_ID=$(openssl rand -hex 8 2>/dev/null || true)
[ -z "$SHORT_ID" ] && error "Short ID 生成失败"

# 订阅路径
# 根因修复：原写法 tr -dc ... < /dev/urandom | head -c 16 中，head 取满 16 字节后退出并
# 关闭管道，tr 继续写入收到 SIGPIPE(141)；在 set -e + pipefail 下该赋值失败会让脚本
# 无任何报错静默退出并触发回滚。改用 openssl 定长输出，无管道截断问题；失败时回退到内核 UUID。
SUB_PATH=$(openssl rand -hex 8 2>/dev/null || true)
[ -z "$SUB_PATH" ] && SUB_PATH=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -dc 'a-f0-9' | head -c 16 || true)
[ -z "$SUB_PATH" ] && error "订阅路径生成失败"

# 伪装 CDN 域名池 REALITY_CDNS 与端口列表 PROXY_PORTS 已在脚本头部统一定义
log "UUID: ${UUID}"
log "公钥: ${PUBLIC_KEY}"
log "伪装 CDN: ${#REALITY_CDNS[@]} 个域名 x 3 种网络类型 = $(( ${#REALITY_CDNS[@]} * 3 )) 个节点"

# ============================================
# 8. 生成 Xray 配置
# ============================================
step "生成 Xray 配置"
mkdir -p /usr/local/etc/xray

# 检测 Xray 服务运行用户（用于后续证书权限设置）
XRAY_USER="root"
XRAY_GROUP="root"
XRAY_USER_ORIG="root"
if command -v systemctl &>/dev/null; then
    for svc_file in /etc/systemd/system/xray.service /usr/lib/systemd/system/xray.service /lib/systemd/system/xray.service; do
        if [ -f "$svc_file" ]; then
            # 官方 xray.service 只有 User= 没有 Group= 行，grep 无匹配返回 1 会在
            # set -e + pipefail 下静默杀死脚本，必须 || true 兜底
            SVC_USER=$(grep -E '^User=' "$svc_file" 2>/dev/null | head -1 | cut -d= -f2 || true)
            SVC_GROUP=$(grep -E '^Group=' "$svc_file" 2>/dev/null | head -1 | cut -d= -f2 || true)
            [ -n "$SVC_USER" ] && XRAY_USER="$SVC_USER"
            [ -n "$SVC_GROUP" ] && XRAY_GROUP="$SVC_GROUP"
            break
        fi
    done
fi
# 验证用户存在，否则回退 root
if ! id "$XRAY_USER" &>/dev/null; then
    XRAY_USER="root"
    XRAY_GROUP="root"
fi
# 如果没有组，取用户的主组
if [ "$XRAY_USER" != "root" ] && [ -z "$SVC_GROUP" ]; then
    XRAY_GROUP=$(id -gn "$XRAY_USER" 2>/dev/null || echo "$XRAY_USER")
fi
XRAY_USER_ORIG="$XRAY_USER"
log "Xray 运行用户: ${XRAY_USER}:${XRAY_GROUP}"

# ============================================
# 循环生成 Reality 入站：每个伪装 CDN 独立端口 + 独立 dest
# dest 与 serverNames 一致，探测时返回对应 CDN 的真实证书
# ============================================
INBOUND_BLOCKS=()
ALL_INBOUND_TAGS=()
for entry in "${REALITY_CDNS[@]}"; do
    CDN_DOMAIN="${entry%%|*}"
    CDN_REST="${entry#*|}"
    CDN_PORT="${CDN_REST%%|*}"
    CDN_TAG="${CDN_REST#*|}"
    ALL_INBOUND_TAGS+=("reality-${CDN_TAG}")

    INBOUND_BLOCKS+=("$(cat <<INBOUND
        {
            "listen": "0.0.0.0",
            "port": ${CDN_PORT},
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "fragment": {
                    "packets": "tlshello",
                    "length": "100-200",
                    "interval": "10-50"
                },
                "realitySettings": {
                    "show": false,
                    "dest": "${CDN_DOMAIN}:443",
                    "xver": 0,
                    "serverNames": [
                        "${CDN_DOMAIN}"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "${SHORT_ID}"
                    ]
                },
                "tcpSettings": {
                    "header": {
                        "type": "none"
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ],
                "routeOnly": true
            },
            "tag": "reality-${CDN_TAG}"
        }
INBOUND
)")
done
# 用逗号连接各入站 JSON 块（去掉最后一个块尾部的逗号）
REALITY_INBOUNDS=$(printf "%s,\n" "${INBOUND_BLOCKS[@]}" | sed '$ s/,$//')
ALL_INBOUND_TAGS+=("vless-tls" "vless-xhttp")

# 路由规则标签列表（JSON 数组格式）
ROUTING_TAGS_JSON=""
for tag in "${ALL_INBOUND_TAGS[@]}"; do
    ROUTING_TAGS_JSON+="\"${tag}\", "
done
ROUTING_TAGS_JSON="${ROUTING_TAGS_JSON%, }"

# XHTTP+Reality 入站：serverNames 覆盖全部伪装域名，dest 用首个域名做反代落地
XHTTP_SERVER_NAMES=""
for entry in "${REALITY_CDNS[@]}"; do
    XHTTP_SERVER_NAMES+="\"${entry%%|*}\", "
done
XHTTP_SERVER_NAMES="${XHTTP_SERVER_NAMES%, }"
XHTTP_DEST_DOMAIN="${REALITY_CDNS[0]%%|*}"

cat > /usr/local/etc/xray/config.json << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "servers": [
            "https://1.1.1.1/dns-query",
            "https://dns.google/dns-query",
            "8.8.8.8",
            "localhost"
        ],
        "queryStrategy": "UseIPv4"
    },
    "inbounds": [
${REALITY_INBOUNDS},
        {
            "listen": "0.0.0.0",
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "fragment": {
                    "packets": "tlshello",
                    "length": "100-200",
                    "interval": "10-50"
                },
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/etc/xray/server.crt",
                            "keyFile": "/etc/xray/server.key"
                        }
                    ]
                },
                "tcpSettings": {
                    "header": {
                        "type": "none"
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ],
                "routeOnly": true
            },
            "tag": "vless-tls"
        },
        {
            "listen": "0.0.0.0",
            "port": 8880,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${XHTTP_DEST_DOMAIN}:443",
                    "xver": 0,
                    "serverNames": [
                        ${XHTTP_SERVER_NAMES}
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "${SHORT_ID}"
                    ]
                },
                "xhttpSettings": {
                    "path": "/xhttp",
                    "mode": "packet-up"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls"
                ]
            },
            "tag": "vless-xhttp"
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4"
            },
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "inboundTag": [${ROUTING_TAGS_JSON}],
                "outboundTag": "direct"
            }
        ]
    }
}
EOF
add_rollback "rm -f /usr/local/etc/xray/config.json"

# 部署前预检：先验证 JSON 合法性，再用 xray 自带测试验证配置语义
jq empty /usr/local/etc/xray/config.json 2>/dev/null || error "config.json 不是合法 JSON"
if ! xray run -test -config /usr/local/etc/xray/config.json >/tmp/xray-test.log 2>&1; then
    cat /tmp/xray-test.log
    error "Xray 配置预检失败，已中止（详见上方输出）"
fi
log "Xray 配置预检通过"

# ============================================
# 9. 生成自签名证书
# ============================================
step "生成自签名证书"
mkdir -p /etc/xray
# 证书 SAN 覆盖所有伪装域名，TLS/XHTTP 节点任意 SNI 均匹配
SAN_LIST="DNS:apple.com"
for entry in "${REALITY_CDNS[@]}"; do
    SAN_LIST+=",DNS:${entry%%|*}"
done

openssl ecparam -genkey -name prime256v1 -out /etc/xray/server.key 2>/dev/null || error "私钥生成失败"
if ! openssl req -new -x509 -days 3650 -key /etc/xray/server.key \
    -out /etc/xray/server.crt \
    -subj "/CN=apple.com" \
    -addext "subjectAltName=${SAN_LIST}" 2>/dev/null; then
    # 旧版 OpenSSL (<1.1.1) 不支持 -addext，回退为无 SAN 证书（客户端 skip-cert-verify 不受影响）
    warn "当前 OpenSSL 不支持 -addext，回退为无 SAN 证书"
    openssl req -new -x509 -days 3650 -key /etc/xray/server.key \
        -out /etc/xray/server.crt \
        -subj "/CN=apple.com" 2>/dev/null || error "证书生成失败"
fi

# 安全设置证书权限
# 公钥可读
chmod 644 /etc/xray/server.crt
# 私钥：根据 xray 运行用户设置权限，避免 644 导致任意用户可读私钥
if [ "$XRAY_USER" = "root" ]; then
    chmod 600 /etc/xray/server.key
else
    if chown "$XRAY_USER:$XRAY_GROUP" /etc/xray /etc/xray/server.key /etc/xray/server.crt 2>/dev/null; then
        chmod 750 /etc/xray
        chmod 640 /etc/xray/server.key
    else
        warn "无法设置证书属主为 ${XRAY_USER}:${XRAY_GROUP}，回退为 root:root 600"
        warn "（若 Xray 启动失败，服务启动阶段会自动重试权限修复）"
        XRAY_USER="root"
        XRAY_GROUP="root"
        chmod 600 /etc/xray/server.key
    fi
fi
add_rollback "rm -f /etc/xray/server.crt /etc/xray/server.key"

# ============================================
# 10. 生成 Clash 订阅配置
# ============================================
step "生成 Clash 订阅配置"

# 确定 Nginx web 根目录（跨发行版）
if [ -d /usr/share/nginx/html ]; then
    WEB_ROOT="/usr/share/nginx/html"
else
    WEB_ROOT="/var/www/html"
fi
mkdir -p "$WEB_ROOT"

# ============================================
# 循环生成节点：5 个伪装 CDN x 3 种网络类型 = 15 个节点
# 节点命名: <类型>-<CDN标签>（如 Reality-Apple-SWDIST），同类型节点归入对应分组
# ============================================
PROXY_BLOCKS=()
GROUP_REALITY=""
GROUP_TLS=""
GROUP_XHTTP=""
for entry in "${REALITY_CDNS[@]}"; do
    CDN_DOMAIN="${entry%%|*}"
    CDN_REST="${entry#*|}"
    CDN_PORT="${CDN_REST%%|*}"
    CDN_TAG="${CDN_REST#*|}"

    PROXY_BLOCKS+=("$(cat <<PROXY
  - name: "Reality-${CDN_TAG}"
    type: vless
    server: ${SERVER_IP}
    port: ${CDN_PORT}
    uuid: ${UUID}
    flow: xtls-rprx-vision
    tls: true
    servername: ${CDN_DOMAIN}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    tcp-opts:
      fragment:
        packets: "tlshello"
        length: "100-200"
        interval: "10-50"
    udp: true

  - name: "TLS-${CDN_TAG}"
    type: vless
    server: ${SERVER_IP}
    port: 8443
    uuid: ${UUID}
    flow: xtls-rprx-vision
    tls: true
    servername: ${CDN_DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: true
    udp: true

  - name: "XHTTP-${CDN_TAG}"
    type: vless
    server: ${SERVER_IP}
    port: 8880
    uuid: ${UUID}
    tls: true
    network: xhttp
    servername: ${CDN_DOMAIN}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    xhttp-opts:
      path: /xhttp
      mode: packet-up
    udp: true
PROXY
)")
    GROUP_REALITY+="      - \"Reality-${CDN_TAG}\""$'\n'
    GROUP_TLS+="      - \"TLS-${CDN_TAG}\""$'\n'
    GROUP_XHTTP+="      - \"XHTTP-${CDN_TAG}\""$'\n'
done
CLASH_PROXIES=$(printf "%s\n" "${PROXY_BLOCKS[@]}")

cat > "$WEB_ROOT/clash.yaml" << CLASHEOF
mixed-port: 7890
allow-lan: false
bind-address: '*'
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'
# 延迟测试统一计时 + TCP 并发拨号，降低握手延迟
unified-delay: true
tcp-concurrent: true
# 全局 uTLS 指纹（无需每个节点单独指定）
global-client-fingerprint: chrome
# 启用进程匹配，applications 规则集中的 PROCESS-NAME 规则才能生效
find-process-mode: strict
# 记住手动选择的节点 + fake-ip 缓存，客户端重启不丢
profile:
  store-selected: true
  store-fake-ip: true

# ============================================
# DNS 优化 (Clash Meta / mihomo)
# - fake-ip 模式加速建连，避免 DNS 污染导致连错 IP
# - 国内域名走阿里/腾讯/114 公共 DNS，解析快
# - fallback 国外 DNS 经代理解析（respect-rules），防污染
# - fallback-filter 按 GeoIP/geosite 判定，被墙域名强制走 fallback
# ============================================
dns:
    enable: true
    ipv6: false
    default-nameserver: [223.5.5.5, 119.29.29.29, 114.114.114.114]
    enhanced-mode: fake-ip
    fake-ip-range: 198.18.0.1/16
    use-hosts: true
    respect-rules: true
    proxy-server-nameserver: [223.5.5.5, 119.29.29.29, 114.114.114.114]
    nameserver: [223.5.5.5, 119.29.29.29, 114.114.114.114]
    fallback: [1.1.1.1, 8.8.8.8]
    fallback-filter: { geoip: true, geoip-code: CN, geosite: [gfw], ipcidr: [240.0.0.0/4], domain: [+.google.com, +.facebook.com, +.youtube.com] }

proxies:
${CLASH_PROXIES}

proxy-groups:
  # 主入口：在三种网络类型分组之间切换（仅手动选择，无 url-test/fallback）
  - name: Proxy
    type: select
    proxies:
      - Reality
      - TLS
      - XHTTP
  # Reality 主力组（推荐）
  - name: Reality
    type: select
    proxies:
${GROUP_REALITY}  # TLS 备用组（自签证书）
  - name: TLS
    type: select
    proxies:
${GROUP_TLS}  # XHTTP 组（Reality 安全层，CDN 兼容）
  - name: XHTTP
    type: select
    proxies:
${GROUP_XHTTP}

# ============================================
# Rule Providers (Loyalsoldier/clash-rules)
# 规则集自动更新，无需手动维护
# ============================================
rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt"
    path: ./ruleset/reject.yaml
    interval: 86400

  icloud:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt"
    path: ./ruleset/icloud.yaml
    interval: 86400

  apple:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt"
    path: ./ruleset/apple.yaml
    interval: 86400

  google:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/google.txt"
    path: ./ruleset/google.yaml
    interval: 86400

  proxy:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt"
    path: ./ruleset/proxy.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: ./ruleset/direct.yaml
    interval: 86400

  private:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: ./ruleset/private.yaml
    interval: 86400

  telegramcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: ./ruleset/telegramcidr.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: ./ruleset/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: ./ruleset/lancidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt"
    path: ./ruleset/applications.yaml
    interval: 86400

# ============================================
# Rules (白名单模式，未命中规则走代理)
# ============================================
rules:
  - RULE-SET,applications,DIRECT
  - DOMAIN,clash.razord.top,DIRECT
  - DOMAIN,yacd.haishan.me,DIRECT
  - RULE-SET,private,DIRECT
  - RULE-SET,reject,REJECT
  - RULE-SET,icloud,Proxy
  - RULE-SET,apple,Proxy
  - RULE-SET,google,Proxy
  - RULE-SET,proxy,Proxy
  - RULE-SET,direct,DIRECT
  - RULE-SET,lancidr,DIRECT
  - RULE-SET,cncidr,DIRECT
  - RULE-SET,telegramcidr,Proxy
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
CLASHEOF
add_rollback "rm -f '$WEB_ROOT/clash.yaml'"

# ============================================
# 11. 配置 Nginx 订阅端点
# ============================================
step "配置 Nginx 订阅端点"

NGINX_CONF="/etc/nginx/conf.d/proxy-sub.conf"

# 彻底清理本脚本生成的旧配置
rm -f /etc/nginx/sites-enabled/proxy-sub 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/proxy-sub-secure 2>/dev/null || true
rm -f /etc/nginx/sites-available/proxy-sub 2>/dev/null || true
rm -f /etc/nginx/sites-available/proxy-sub-secure 2>/dev/null || true
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
# 发行版默认 vhost 不直接删除，重命名禁用以便恢复
for f in /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default; do
    [ -e "$f" ] || [ -L "$f" ] && mv -f "$f" "${f}.disabled-by-proxy" 2>/dev/null || true
done
service_manage stop nginx 2>/dev/null || true
sleep 1

# WEB_ROOT 已在 Clash 配置步骤中确定，确保目录存在
mkdir -p "$WEB_ROOT"

# 创建订阅配置（使用 root+try_files 替代 alias，避免 Nginx 版本兼容性问题）
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen ${SUB_PORT};
    server_name _;

    # 订阅端点不写访问日志，减少日志噪音并保护订阅路径隐私
    access_log off;

    # 安全头
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 只允许特定路径访问订阅
    location = /${SUB_PATH} {
        root ${WEB_ROOT};
        try_files /clash.yaml =404;
        default_type text/yaml;
        charset utf-8;
        add_header Content-Disposition 'attachment; filename="clash.yaml"' always;
    }

    # 拒绝所有其他请求
    location / {
        return 404;
    }
}
NGINXEOF

# 设置 SELinux 上下文（CentOS/RHEL/Fedora），防止 403 Forbidden
if command -v chcon &>/dev/null && command -v selinuxenabled &>/dev/null; then
    if selinuxenabled 2>/dev/null; then
        chcon -Rt httpd_sys_content_t "$WEB_ROOT" 2>/dev/null || true
    fi
fi

add_rollback "rm -f '$NGINX_CONF'; service_manage restart nginx 2>/dev/null || true"

nginx -t 2>&1 && service_manage restart nginx || {
    warn "Nginx 配置测试失败"
    rm -f "$NGINX_CONF"
    service_manage restart nginx 2>/dev/null || true
    error "Nginx 配置错误，请检查端口 ${SUB_PORT} 是否被占用"
}

# ============================================
# 12. 配置服务限制并启动
# ============================================
step "配置服务并启动"

if command -v systemctl &>/dev/null; then
    mkdir -p /etc/systemd/system/xray.service.d
    # 注意：StartLimitBurst/StartLimitIntervalSec 是 [Unit] 段指令，放 [Service] 会被 systemd 忽略
    cat > /etc/systemd/system/xray.service.d/limits.conf << 'SYSTEMD'
[Unit]
StartLimitBurst=3
StartLimitIntervalSec=60

[Service]
LimitNOFILE=131072
LimitNPROC=32768
Restart=always
RestartSec=5
SYSTEMD
    add_rollback "rm -f /etc/systemd/system/xray.service.d/limits.conf"

    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/limits.conf << 'SYSTEMD'
[Service]
LimitNOFILE=131072
SYSTEMD
    add_rollback "rm -f /etc/systemd/system/nginx.service.d/limits.conf"

    systemctl daemon-reload 2>/dev/null || true
fi

# 启动失败不在此处中断，交由下方 is_service_active 检查输出 journalctl 诊断后再统一报错
service_manage enable xray 2>/dev/null || true
service_manage restart xray 2>/dev/null || true

sleep 2

if is_service_active xray; then
    log "Xray 服务启动成功"
else
    # 证书权限自动修复重试（无论之前 chown 是否成功，统一以实际属主重设一次）
    if [ "$XRAY_USER_ORIG" != "root" ]; then
        warn "Xray 启动失败，尝试修复证书权限后重试..."
        ORIG_GROUP=$(id -gn "$XRAY_USER_ORIG" 2>/dev/null || echo "$XRAY_USER_ORIG")
        chown "${XRAY_USER_ORIG}:${ORIG_GROUP}" /etc/xray /etc/xray/server.key /etc/xray/server.crt 2>/dev/null || true
        chmod 750 /etc/xray 2>/dev/null || true
        chmod 640 /etc/xray/server.key 2>/dev/null || true
        service_manage restart xray 2>/dev/null || true
        sleep 2
    fi
    if is_service_active xray; then
        log "Xray 服务启动成功（证书权限已自动修复）"
    else
        warn "Xray 服务启动失败，查看日志:"
        journalctl -u xray --no-pager -n 20 2>/dev/null || true
        error "Xray 服务启动失败"
    fi
fi

service_manage enable nginx 2>/dev/null || true
service_manage restart nginx 2>/dev/null || true

# ============================================
# 13. 创建管理脚本
# ============================================
step "创建管理脚本"

cat > /etc/proxy-manager.env << ENVEOF
# proxy-manager 运行参数（由 install.sh 生成，重装时自动更新）
PROXY_PORTS="${PROXY_PORTS[*]}"
REALITY_PORTS="${REALITY_PORTS[*]}"
CDN_LABELS="${CDN_LABELS}"
NODE_TYPES="Reality TLS XHTTP"
ENVEOF

cat > /usr/local/bin/proxy-manager << 'MGRSCRIPT'
#!/bin/bash
# Xray Proxy Manager v4.3
# https://github.com/Evergreen05/xray-proxy-install

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 部署参数（由 install.sh 写入，缺失时回退默认值）
[ -f /etc/proxy-manager.env ] && . /etc/proxy-manager.env
PROXY_PORTS=${PROXY_PORTS:-"443 1443 2443 3443 4443 8443 8880"}
REALITY_PORTS=${REALITY_PORTS:-"443 1443 2443 3443 4443"}
CDN_LABELS=${CDN_LABELS:-"Apple-SWDIST Apple-iTunes Apple-Update Microsoft-CDN Bing"}
NODE_TYPES=${NODE_TYPES:-"Reality TLS XHTTP"}

service_manage() {
    local action=$1
    local service=$2
    if command -v systemctl &>/dev/null; then
        systemctl "$action" "$service"
    elif command -v service &>/dev/null; then
        case "$action" in
            enable)  update-rc.d "$service" defaults 2>/dev/null || chkconfig "$service" on 2>/dev/null || true ;;
            start)   service "$service" start ;;
            stop)    service "$service" stop ;;
            restart) service "$service" restart ;;
            status)  service "$service" status ;;
        esac
    elif command -v rc-service &>/dev/null; then
        case "$action" in
            enable)  rc-update add "$service" default 2>/dev/null || true ;;
            start)   rc-service "$service" start ;;
            stop)    rc-service "$service" stop ;;
            restart) rc-service "$service" restart ;;
            status)  rc-service "$service" status ;;
        esac
    fi
}

is_service_active() {
    if command -v systemctl &>/dev/null; then
        systemctl is-active --quiet "$1"
    elif command -v rc-service &>/dev/null; then
        rc-service "$1" status &>/dev/null
    else
        pgrep -x "$1" &>/dev/null
    fi
}

show_info() {
    SERVER_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ip.sb 2>/dev/null || echo "unknown")
    UUID=$(cat /usr/local/etc/xray/config.json 2>/dev/null | jq -r '.inbounds[0].settings.clients[0].id' 2>/dev/null || echo "unknown")

    NGINX_CONF=""
    for conf in /etc/nginx/conf.d/proxy-sub.conf /etc/nginx/sites-available/proxy-sub-secure; do
        [ -f "$conf" ] && NGINX_CONF="$conf" && break
    done

    # 使用 sed 提取（兼容无 grep -P 的系统）
    SUB_PORT=$(sed -n 's/.*listen \([0-9]*\).*/\1/p' "$NGINX_CONF" 2>/dev/null | head -1)
    SUB_PATH=$(sed -n 's/.*location = \/\([a-z0-9]*\).*/\1/p' "$NGINX_CONF" 2>/dev/null | head -1)

    PRIVATE_KEY=$(cat /usr/local/etc/xray/config.json 2>/dev/null | jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' 2>/dev/null)
    if [ -n "$PRIVATE_KEY" ] && [ "$PRIVATE_KEY" != "null" ]; then
        PUB_OUT=$(xray x25519 -i "$PRIVATE_KEY" 2>&1 || true)
        PUBLIC_KEY=$(echo "$PUB_OUT" | grep -iE '(public|公钥).*(key|密钥)' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r' | tr -d '[:space:]' | head -1)
        if [ -z "$PUBLIC_KEY" ]; then
            PUBLIC_KEY=$(echo "$PUB_OUT" | grep -oE '[A-Za-z0-9+/_-]{42,45}={0,2}' | head -1)
        fi
        [ -z "$PUBLIC_KEY" ] && PUBLIC_KEY="unknown"
    else
        PUBLIC_KEY="unknown"
    fi

    echo -e "${BLUE}========== 服务器信息 ==========${NC}"
    echo -e "${GREEN}IP:${NC}       ${SERVER_IP}"
    echo -e "${GREEN}UUID:${NC}     ${UUID}"
    echo -e "${GREEN}公钥:${NC}     ${PUBLIC_KEY}"
    echo ""
    echo -e "${BLUE}========== 订阅信息 ==========${NC}"
    echo -e "${GREEN}订阅链接:${NC}"
    echo "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    echo ""
    echo -e "${YELLOW}提示: 请确保云服务器安全组已放行端口 ${SUB_PORT}${NC}"
    echo ""
    echo -e "${BLUE}========== 节点信息 ==========${NC}"
    local _ncount _i _label _port
    _ncount=$(echo $CDN_LABELS | wc -w)
    echo -e "${YELLOW}共 $((_ncount * 3)) 个节点 = ${_ncount} 个伪装 CDN x 3 组 (Reality/TLS/XHTTP)${NC}"
    for _type in $NODE_TYPES; do
        echo ""
        case "$_type" in
            Reality) echo -e "${GREEN}[Reality 组 - 主力推荐]${NC}" ;;
            TLS)     echo -e "${GREEN}[TLS 组 - 备用，自签证书，端口 8443]${NC}" ;;
            XHTTP)   echo -e "${GREEN}[XHTTP 组 - Reality 安全层，端口 8880]${NC}" ;;
            *)       echo -e "${GREEN}[${_type} 组]${NC}" ;;
        esac
        _i=1
        for _label in $CDN_LABELS; do
            if [ "$_type" = "Reality" ]; then
                _port=$(echo "$REALITY_PORTS" | cut -d' ' -f$_i)
                printf "  %-24s %s:%s\n" "${_type}-${_label}" "${SERVER_IP}" "${_port}"
            else
                echo "  ${_type}-${_label}"
            fi
            _i=$((_i + 1))
        done
    done
}

port_check() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -q ":${port} "
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} "
    else
        false
    fi
}

# 提取订阅地址（供 sub 命令使用）
get_sub_url() {
    local conf=""
    for c in /etc/nginx/conf.d/proxy-sub.conf /etc/nginx/sites-available/proxy-sub-secure; do
        [ -f "$c" ] && conf="$c" && break
    done
    [ -z "$conf" ] && return 1
    local port path ip
    port=$(sed -n 's/.*listen \([0-9]*\).*/\1/p' "$conf" 2>/dev/null | head -1)
    path=$(sed -n 's/.*location = \/\([a-z0-9]*\).*/\1/p' "$conf" 2>/dev/null | head -1)
    ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ip.sb 2>/dev/null || echo "<服务器IP>")
    [ -n "$port" ] && [ -n "$path" ] && echo "http://${ip}:${port}/${path}"
}

test_config() {
    echo -e "${BLUE}========== 配置测试 ==========${NC}"
    if xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1; then
        echo -e "Xray 配置:  ${GREEN}通过${NC}"
    else
        echo -e "Xray 配置:  ${RED}失败${NC}"
        xray run -test -config /usr/local/etc/xray/config.json 2>&1 | tail -5
    fi
    if nginx -t >/dev/null 2>&1; then
        echo -e "Nginx 配置: ${GREEN}通过${NC}"
    else
        echo -e "Nginx 配置: ${RED}失败${NC}"
        nginx -t 2>&1 | tail -5
    fi
}

case "$1" in
    status)
        echo -e "${GREEN}=== Xray 服务状态 ===${NC}"
        if is_service_active xray; then echo "Xray: 运行中"; else echo "Xray: 未运行"; fi
        echo ""
        echo -e "${GREEN}=== Nginx 服务状态 ===${NC}"
        if is_service_active nginx; then echo "Nginx: 运行中"; else echo "Nginx: 未运行"; fi
        echo ""
        echo -e "${GREEN}=== 端口监听 ===${NC}"
        for port in $PROXY_PORTS; do
            if port_check "$port"; then echo -e "  端口 ${port}: ${GREEN}正常${NC}"; else echo -e "  端口 ${port}: ${RED}未监听${NC}"; fi
        done
        ;;
    restart)
        echo -e "${YELLOW}重启服务...${NC}"
        service_manage restart xray
        service_manage restart nginx
        echo -e "${GREEN}服务已重启${NC}"
        ;;
    stop)
        echo -e "${YELLOW}停止服务...${NC}"
        service_manage stop xray
        service_manage stop nginx
        echo -e "${GREEN}服务已停止${NC}"
        ;;
    start)
        echo -e "${YELLOW}启动服务...${NC}"
        service_manage start xray
        service_manage start nginx
        echo -e "${GREEN}服务已启动${NC}"
        ;;
    config)
        echo -e "${GREEN}Xray 配置:${NC}"
        cat /usr/local/etc/xray/config.json | jq .
        ;;
    rules)
        RULES_PATH="/var/www/html/clash.yaml"
        [ -f "/usr/share/nginx/html/clash.yaml" ] && RULES_PATH="/usr/share/nginx/html/clash.yaml"
        echo -e "${GREEN}Clash 规则文件:${NC}"
        echo "$RULES_PATH"
        echo ""
        echo -e "${YELLOW}修改后重启 Nginx 使其生效${NC}"
        ;;
    log)
        echo -e "${GREEN}Xray 日志 (最近50行):${NC}"
        journalctl -u xray --no-pager -n 50 2>/dev/null || cat /var/log/xray/*.log 2>/dev/null | tail -50 || echo "无法读取日志"
        ;;
    info)
        show_info
        ;;
    sub)
        get_sub_url || echo -e "${RED}未找到订阅配置${NC}"
        ;;
    test)
        test_config
        ;;
    uninstall)
        echo -e "${RED}即将卸载代理服务!${NC}"
        read -p "确认卸载？(y/n): " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo "已取消"
            exit 0
        fi
        service_manage stop xray 2>/dev/null || true
        service_manage stop nginx 2>/dev/null || true
        service_manage disable xray 2>/dev/null || true
        rm -f /usr/local/etc/xray/config.json
        rm -f /etc/xray/server.crt /etc/xray/server.key
        rm -f /etc/nginx/conf.d/proxy-sub.conf
        rm -f /etc/nginx/sites-available/proxy-sub-secure
        rm -f /etc/nginx/sites-enabled/proxy-sub-secure
        rm -f /var/www/html/clash.yaml
        rm -f /usr/share/nginx/html/clash.yaml
        rm -f /usr/local/bin/proxy-manager
        rm -f /etc/sysctl.d/99-proxy-optimized.conf
        rm -f /etc/security/limits.d/99-proxy.conf
        rm -rf /etc/systemd/system/xray.service.d
        rm -rf /etc/systemd/system/nginx.service.d
        rm -f /etc/proxy-manager.env
        if command -v systemctl &>/dev/null; then
            systemctl daemon-reload 2>/dev/null || true
        fi
        bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null || true
        sysctl --system >/dev/null 2>&1 || true
        echo -e "${GREEN}卸载完成${NC}"
        ;;
    *)
        echo -e "${BLUE}Xray Proxy Manager v4.3${NC}"
        echo -e "GitHub: https://github.com/Evergreen05/xray-proxy-install"
        echo ""
        echo "用法: proxy-manager <命令>"
        echo ""
        echo "命令:"
        echo "  status    - 查看服务状态和端口"
        echo "  restart   - 重启所有服务"
        echo "  stop      - 停止所有服务"
        echo "  start     - 启动所有服务"
        echo "  config    - 查看 Xray 配置"
        echo "  rules     - 查看 Clash 规则路径"
        echo "  log       - 查看 Xray 日志"
        echo "  info      - 查看服务器和订阅信息"
        echo "  sub       - 仅输出订阅地址"
        echo "  test      - 测试 Xray 与 Nginx 配置"
        echo "  uninstall - 卸载代理服务"
        ;;
esac
MGRSCRIPT

chmod +x /usr/local/bin/proxy-manager
add_rollback "rm -f /usr/local/bin/proxy-manager"

# ============================================
# 14. 防火墙放行与健康检查
# ============================================
step "防火墙放行与健康检查"

open_firewall_port() {
    local port=$1 opened=0
    # ufw (Debian/Ubuntu)：已启用时优先
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "$port/tcp" >/dev/null 2>&1 && { log "ufw: 放行 ${port}"; opened=1; }
    fi
    # firewalld (RHEL/CentOS/Fedora)：仅在服务实际运行时尝试
    if [ "$opened" -eq 0 ] && command -v firewall-cmd &>/dev/null; then
        if systemctl is-active --quiet firewalld 2>/dev/null || service firewalld status >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 && { log "firewalld: 放行 ${port}"; opened=1; }
        fi
    fi
    # iptables 通用回退（含规则持久化）
    if [ "$opened" -eq 0 ] && command -v iptables &>/dev/null; then
        if iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            log "iptables: 端口 ${port} 已放行"
        elif iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            log "iptables: 放行 ${port}"
        fi
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save >/dev/null 2>&1 || true
        elif command -v iptables-save &>/dev/null && [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        elif command -v service &>/dev/null && service iptables status >/dev/null 2>&1; then
            service iptables save >/dev/null 2>&1 || true
        fi
    fi
}

for port in "${PROXY_PORTS[@]}" "$SUB_PORT"; do
    open_firewall_port "$port"
done

HEALTH_OK=1
is_service_active xray && log "Xray: 运行中" || { warn "Xray: 未运行"; HEALTH_OK=0; }
is_service_active nginx && log "Nginx: 运行中" || { warn "Nginx: 未运行"; HEALTH_OK=0; }
for port in "${PROXY_PORTS[@]}"; do
    check_port "$port" && log "端口 ${port}: 正常" || { warn "端口 ${port}: 未监听"; HEALTH_OK=0; }
done
SUB_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${SUB_PORT}/${SUB_PATH}" 2>/dev/null || echo "000")
if [ "$SUB_HTTP_CODE" = "200" ]; then
    log "订阅端点: 可访问"
else
    warn "订阅端点: HTTP ${SUB_HTTP_CODE}（不可访问）"
    HEALTH_OK=0
fi

[ "$HEALTH_OK" -eq 0 ] && warn "部分服务异常，请检查日志: proxy-manager log"

DEPLOY_SUCCESS=1

# 部署成功，清理覆盖安装前的配置备份
rm -f /usr/local/etc/xray/config.json.prevbak /etc/xray/server.crt.prevbak /etc/xray/server.key.prevbak 2>/dev/null || true

# ============================================
# 15. 输出部署结果
# ============================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}           ${GREEN}跨境电商网络代理部署完成!${NC}                          ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}========== 服务器信息 ==========${NC}"
echo -e "${GREEN}服务器 IP:${NC}    ${SERVER_IP}"
echo -e "${GREEN}UUID:${NC}          ${UUID}"
echo -e "${GREEN}公钥:${NC}          ${PUBLIC_KEY}"
echo -e "${GREEN}Short ID:${NC}      ${SHORT_ID}"
echo ""
echo -e "${CYAN}========== 订阅地址 ==========${NC}"
echo -e "${GREEN}订阅链接:${NC}"
echo ""
echo -e "${YELLOW}  http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}${NC}"
echo ""
echo -e "${GREEN}订阅文件:${NC}  ${WEB_ROOT}/clash.yaml"
echo ""
echo -e "${CYAN}========== 节点信息 (共 $(( ${#REALITY_CDNS[@]} * 3 )) 个) ==========${NC}"
echo -e "${YELLOW}主组 Proxy 下分 Reality / TLS / XHTTP 三个分组，每组 ${#REALITY_CDNS[@]} 个节点${NC}"
echo ""
echo -e "${GREEN}[Reality 组 - 主力推荐]${NC}"
for entry in "${REALITY_CDNS[@]}"; do
    _d="${entry%%|*}"; _r="${entry#*|}"; _p="${_r%%|*}"; _t="${_r#*|}"
    printf "  %-24s 端口 %-5s CDN: %s\n" "Reality-${_t}" "${_p}" "${_d}"
done
echo ""
echo -e "${GREEN}[TLS 组 - 备用，端口 8443，自签证书]${NC}"
_tls_nodes=""
for entry in "${REALITY_CDNS[@]}"; do _tls_nodes+="TLS-${entry##*|} / "; done
echo "  ${_tls_nodes%/ }"
echo ""
echo -e "${GREEN}[XHTTP 组 - Reality 安全层，端口 8880]${NC}"
_xhttp_nodes=""
for entry in "${REALITY_CDNS[@]}"; do _xhttp_nodes+="XHTTP-${entry##*|} / "; done
echo "  ${_xhttp_nodes%/ }"
echo ""
echo -e "${CYAN}========== 一键部署 ==========${NC}"
echo -e "${GREEN}快速安装命令:${NC}"
echo ""
echo -e "${YELLOW}  bash <(curl -fsSL https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh) -y${NC}"
echo ""
echo -e "${GREEN}或手动下载:${NC}  wget https://raw.githubusercontent.com/Evergreen05/xray-proxy-install/main/install.sh && bash install.sh -y"
echo ""
echo -e "${CYAN}========== 管理命令 ==========${NC}"
echo -e "${GREEN}proxy-manager info${NC}     - 查看服务器和订阅信息"
echo -e "${GREEN}proxy-manager sub${NC}      - 仅输出订阅地址"
echo -e "${GREEN}proxy-manager status${NC}   - 查看服务状态"
echo -e "${GREEN}proxy-manager test${NC}     - 测试 Xray 与 Nginx 配置"
echo -e "${GREEN}proxy-manager restart${NC}  - 重启服务"
echo -e "${GREEN}proxy-manager log${NC}      - 查看日志"
echo -e "${GREEN}proxy-manager uninstall${NC} - 卸载代理服务"
echo ""
echo -e "${CYAN}GitHub:${NC} https://github.com/Evergreen05/xray-proxy-install"
echo ""
echo -e "${RED}重要提醒:${NC}"
echo -e "1. 请在云服务器控制台安全组放行端口: ${YELLOW}${PROXY_PORTS[*]} ${SUB_PORT}${NC}"
echo -e "2. 请保存以上信息，用于配置客户端"
echo -e "3. 请勿将订阅链接分享给他人"
echo -e "4. TLS(8443) 组节点使用自签证书，客户端需启用 skip-cert-verify（Reality/XHTTP 组无需此项）"
echo -e "5. XHTTP(8880) 组使用 Reality 安全层，需较新版本 mihomo/Clash Meta 内核"
echo -e "6. 订阅链接为 HTTP 明文传输，建议在可信网络环境下载"
echo -e "${BLUE}============================================================${NC}"
