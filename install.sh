#!/bin/bash
set -e

# ============================================
# Xray Proxy Install Script v4.1
# Protocol: VLESS + Reality + Vision + Fragment
# Optimization: BBR / TCP / Subscription endpoint / Auto Swap
# Cross-platform: apt/dnf/yum/pacman/zypper/apk
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
    echo "$1" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

# ============================================
# 1. 系统检测与权限检查
# ============================================
[[ $EUID -ne 0 ]] && error "请使用 root 权限运行此脚本"
detect_distro

# ============================================
# 2. 端口冲突检测与 IP 获取
# ============================================
step "端口冲突检测与 IP 获取"

PORT_CONFLICT=0
for port in 443 8443 8880 10707; do
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

# IP 获取（多源容错，不使用 grep -P）
SERVER_IP=""
for src in ifconfig.me ipinfo.io/ip ip.sb icanhazip.com; do
    RESP=$(curl -s --connect-timeout 5 --max-time 10 "https://${src}" 2>/dev/null || true)
    SERVER_IP=$(extract_ip "$RESP")
    [ -n "$SERVER_IP" ] && break
done
[ -z "$SERVER_IP" ] && error "无法获取服务器公网 IP"
log "服务器 IP: ${SERVER_IP}"

# ============================================
# 3. 内存检查与 Swap 配置
# ============================================
step "内存检查与 Swap 配置"

TOTAL_RAM_MB=$(awk '/MemTotal/ {printf "%d", ($2+512)/1024}' /proc/meminfo)
TOTAL_SWAP_MB=$(awk '/SwapTotal/ {printf "%d", ($2+512)/1024}' /proc/meminfo)

echo ""
echo -e "${CYAN}========== 内存检查 ==========${NC}"
echo -e "${GREEN}物理内存:${NC}  ${TOTAL_RAM_MB} MB"
echo -e "${GREEN}Swap 大小:${NC} ${TOTAL_SWAP_MB} MB"
echo ""

if [ "$TOTAL_SWAP_MB" -ge 2000 ]; then
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
# 4. 环境检查
# ============================================
step "环境检查"

if command -v xray &>/dev/null && [ -f /usr/local/etc/xray/config.json ]; then
    warn "检测到已安装 Xray，将进行覆盖安装"
    service_manage stop xray 2>/dev/null || true
    sleep 1
    pkill -f "xray" 2>/dev/null || true
fi

for _svc in nginx apache2 httpd caddy; do
    if command -v "$_svc" &>/dev/null; then
        service_manage stop "$_svc" 2>/dev/null || true
    fi
done
sleep 1
pkill -f "nginx" 2>/dev/null || true
pkill -f "apache2|httpd" 2>/dev/null || true

# 清理旧 Nginx 配置残留
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

# ============================================
# 5. 系统更新与依赖安装
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
# 6. 网络内核优化
# ============================================
step "网络内核优化"

# 根据内存动态计算 tcp_mem（单位：页，1页=4KB）
# low=物理内存*25%, pressure=50%, high=75%
TCP_MEM_LOW=$(( TOTAL_RAM_MB * 256 / 4 ))
TCP_MEM_PRESSURE=$(( TOTAL_RAM_MB * 512 / 4 ))
TCP_MEM_HIGH=$(( TOTAL_RAM_MB * 768 / 4 ))

# 备份原始配置
cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%s) 2>/dev/null || true
add_rollback "rm -f /etc/sysctl.d/99-proxy-optimized.conf; sysctl --system >/dev/null 2>&1 || true"

cat > /etc/sysctl.d/99-proxy-optimized.conf << 'SYSCTL'
# ============================================
# 网络内核优化 (适配 200M 带宽)
# ============================================

# --- BBR 拥塞控制 ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# --- TCP 缓冲区 (8MB，平衡内存与性能) ---
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
# 7. 安装 Xray-core
# ============================================
step "安装 Xray-core"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
command -v xray &>/dev/null || error "Xray 安装失败，请检查网络或手动安装"
add_rollback "bash -c \"\$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ remove 2>/dev/null || true"

# Xray 安装脚本会自动启动服务，先停止它，等待我们生成配置后再启动
service_manage stop xray 2>/dev/null || true
sleep 1
# 兜底：确保没有残留的 xray 进程占用端口
pkill -f "/usr/local/bin/xray" 2>/dev/null || true
sleep 1

# ============================================
# 8. 生成配置参数
# ============================================
step "生成配置参数"
UUID=$(xray uuid 2>/dev/null || true)
[ -z "$UUID" ] && error "UUID 生成失败，请检查 xray 是否正确安装"

# 生成 X25519 密钥对（兼容多种 Xray 版本输出格式）
PRIVATE_KEY=""
PUBLIC_KEY=""
KEYS=$(xray x25519 2>&1 || true)

# 模式1: "Private key: xxx" / "PrivateKey: xxx" / "私钥: xxx"
if [ -z "$PRIVATE_KEY" ]; then
    PRIVATE_KEY=$(echo "$KEYS" | grep -iE '(private|私钥).*(key|密钥)' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r' | tr -d '[:space:]' | head -1)
fi
if [ -z "$PUBLIC_KEY" ]; then
    PUBLIC_KEY=$(echo "$KEYS" | grep -iE '(public|公钥).*(key|密钥)' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r' | tr -d '[:space:]' | head -1)
fi

# 模式2: JSON 输出 {"privateKey":"xxx","publicKey":"xxx"}
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    JSON_KEYS=$(echo "$KEYS" | grep -oE '\{[^}]*"privateKey"[^}]*\}')
    if [ -n "$JSON_KEYS" ] && command -v jq &>/dev/null; then
        PRIVATE_KEY=$(echo "$JSON_KEYS" | jq -r '.privateKey // empty' 2>/dev/null)
        PUBLIC_KEY=$(echo "$JSON_KEYS" | jq -r '.publicKey // empty' 2>/dev/null)
    fi
fi

# 模式3: 逐行解析，找看起来像 base64 密钥的字符串（43-44字符，base64字符集）
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    B64_KEYS=$(echo "$KEYS" | grep -oE '[A-Za-z0-9+/]{42,45}={0,2}' | head -2)
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
        OPENSSL_VER=$(openssl version 2>/dev/null | awk '{print $2}')
        # OpenSSL 1.1.0+ 支持 x25519
        TMP_PRIV_DER=$(openssl genpkey -algorithm x25519 -outform DER 2>/dev/null | base64 -w 0 2>/dev/null)
        if [ -n "$TMP_PRIV_DER" ]; then
            # DER 格式中最后 32 字节是私钥原始值（RFC 8410 PKCS#8 末尾 OCTET STRING）
            PRIVATE_KEY=$(echo "$TMP_PRIV_DER" | base64 -d 2>/dev/null | tail -c 32 | base64 -w 0 2>/dev/null)
            # 用私钥 DER 生成公钥（通过 openssl pkey 提取）
            TMP_PUB_DER=$(echo "$TMP_PRIV_DER" | base64 -d 2>/dev/null | openssl pkey -pubout -inform DER -outform DER 2>/dev/null | base64 -w 0 2>/dev/null)
            if [ -n "$TMP_PUB_DER" ]; then
                PUBLIC_KEY=$(echo "$TMP_PUB_DER" | base64 -d 2>/dev/null | tail -c 32 | base64 -w 0 2>/dev/null)
            fi
        fi
        # 如果 openssl x25519 不支持，尝试用 xray 本身的其他方式
        if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
            # 尝试直接解析 xray x25519 的纯文本输出（无 key: 标签格式）
            PRIVATE_KEY=$(echo "$KEYS" | grep -v '^$' | grep -v '^[[:space:]]*#' | head -1 | tr -d '\r' | tr -d '[:space:]')
            PUBLIC_KEY=$(echo "$KEYS" | grep -v '^$' | grep -v '^[[:space:]]*#' | sed -n '2p' | tr -d '\r' | tr -d '[:space:]')
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

SHORT_ID=$(openssl rand -hex 8)
[ -z "$SHORT_ID" ] && error "Short ID 生成失败"

# 订阅路径
SUB_PATH=$(tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 16)
[ -z "$SUB_PATH" ] && SUB_PATH=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -dc 'a-z0-9' | head -c 16)
SUB_PORT=10707

log "UUID: ${UUID}"
log "公钥: ${PUBLIC_KEY}"

# ============================================
# 9. 生成 Xray 配置
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
            SVC_USER=$(grep -E '^User=' "$svc_file" 2>/dev/null | head -1 | cut -d= -f2)
            SVC_GROUP=$(grep -E '^Group=' "$svc_file" 2>/dev/null | head -1 | cut -d= -f2)
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

cat > /usr/local/etc/xray/config.json << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 443,
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
                    "dest": "swdist.apple.com:443",
                    "xver": 0,
                    "serverNames": [
                        "swdist.apple.com"
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
            "tag": "vless-reality"
        },
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
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/etc/xray/server.crt",
                            "keyFile": "/etc/xray/server.key"
                        }
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
                "inboundTag": [
                    "vless-reality",
                    "vless-tls"
                ],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "inboundTag": [
                    "vless-xhttp"
                ],
                "outboundTag": "direct"
            }
        ]
    }
}
EOF
add_rollback "rm -f /usr/local/etc/xray/config.json"

# ============================================
# 10. 生成自签名证书
# ============================================
step "生成自签名证书"
mkdir -p /etc/xray
openssl ecparam -genkey -name prime256v1 -out /etc/xray/server.key 2>/dev/null || error "私钥生成失败"
openssl req -new -x509 -days 3650 -key /etc/xray/server.key \
    -out /etc/xray/server.crt \
    -subj "/CN=apple.com" 2>/dev/null || error "证书生成失败"

# 安全设置证书权限
# 公钥可读
chmod 644 /etc/xray/server.crt
# 私钥：根据 xray 运行用户设置权限，避免 644 导致任意用户可读私钥
CERT_PERM_OK=1
if [ "$XRAY_USER" = "root" ]; then
    chmod 600 /etc/xray/server.key
else
    if chown "$XRAY_USER:$XRAY_GROUP" /etc/xray /etc/xray/server.key /etc/xray/server.crt 2>/dev/null; then
        chmod 750 /etc/xray
        chmod 640 /etc/xray/server.key
    else
        warn "无法设置证书属主为 ${XRAY_USER}:${XRAY_GROUP}，回退为 root:root 600"
        warn "若 Xray 启动失败（证书权限错误），请手动执行: chown ${XRAY_USER}:${XRAY_GROUP} /etc/xray/server.key && chmod 640 /etc/xray/server.key"
        XRAY_USER="root"
        XRAY_GROUP="root"
        chmod 600 /etc/xray/server.key
        CERT_PERM_OK=0
    fi
fi
add_rollback "rm -f /etc/xray/server.crt /etc/xray/server.key"

# ============================================
# 11. 生成 Clash 订阅配置
# ============================================
step "生成 Clash 订阅配置"

# 确定 Nginx web 根目录（跨发行版）
if [ -d /usr/share/nginx/html ]; then
    WEB_ROOT="/usr/share/nginx/html"
else
    WEB_ROOT="/var/www/html"
fi
mkdir -p "$WEB_ROOT"

cat > "$WEB_ROOT/clash.yaml" << CLASHEOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
  - name: Reality-Fragment
    type: vless
    server: ${SERVER_IP}
    port: 443
    uuid: ${UUID}
    flow: xtls-rprx-vision
    tls: true
    servername: swdist.apple.com
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

  - name: VLESS-TLS
    type: vless
    server: ${SERVER_IP}
    port: 8443
    uuid: ${UUID}
    flow: xtls-rprx-vision
    tls: true
    servername: apple.com
    client-fingerprint: chrome
    skip-cert-verify: true
    udp: true

  - name: XHTTP-TLS
    type: vless
    server: ${SERVER_IP}
    port: 8880
    uuid: ${UUID}
    tls: true
    network: xhttp
    servername: apple.com
    skip-cert-verify: true
    client-fingerprint: chrome
    xhttp-opts:
      path: /xhttp
      mode: packet-up
    udp: true

proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Reality-Fragment
      - VLESS-TLS
      - XHTTP-TLS
      - DIRECT

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

  gfw:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: ./ruleset/gfw.yaml
    interval: 86400

  tld-not-cn:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt"
    path: ./ruleset/tld-not-cn.yaml
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
# 12. 配置 Nginx 订阅端点
# ============================================
step "配置 Nginx 订阅端点"

NGINX_CONF="/etc/nginx/conf.d/proxy-sub.conf"

# 彻底清理旧配置
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/proxy-sub 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/proxy-sub-secure 2>/dev/null || true
rm -f /etc/nginx/sites-available/default 2>/dev/null || true
rm -f /etc/nginx/sites-available/proxy-sub 2>/dev/null || true
rm -f /etc/nginx/sites-available/proxy-sub-secure 2>/dev/null || true
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
service_manage stop nginx 2>/dev/null || true
sleep 1

# WEB_ROOT 已在 Clash 配置步骤中确定，确保目录存在
mkdir -p "$WEB_ROOT"

# 创建订阅配置（使用 root+try_files 替代 alias，避免 Nginx 版本兼容性问题）
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen ${SUB_PORT};
    server_name _;

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
# 13. 配置服务限制并启动
# ============================================
step "配置服务并启动"

if command -v systemctl &>/dev/null; then
    mkdir -p /etc/systemd/system/xray.service.d
    cat > /etc/systemd/system/xray.service.d/limits.conf << 'SYSTEMD'
[Service]
LimitNOFILE=131072
LimitNPROC=32768
Restart=always
RestartSec=5
StartLimitBurst=3
StartLimitIntervalSec=60
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

service_manage enable xray
service_manage restart xray

sleep 2

if is_service_active xray; then
    log "Xray 服务启动成功"
else
    warn "Xray 服务启动失败，查看日志:"
    journalctl -u xray --no-pager -n 20 2>/dev/null || true
    if [ "$XRAY_USER_ORIG" != "root" ]; then
        warn "可能是证书权限问题，尝试: chown ${XRAY_USER_ORIG}:$(id -gn ${XRAY_USER_ORIG} 2>/dev/null || echo ${XRAY_USER_ORIG}) /etc/xray/server.key && chmod 640 /etc/xray/server.key && service_manage restart xray"
    fi
    error "Xray 服务启动失败"
fi

service_manage enable nginx 2>/dev/null || true
service_manage restart nginx 2>/dev/null || true

# ============================================
# 14. 创建管理脚本
# ============================================
step "创建管理脚本"

cat > /usr/local/bin/proxy-manager << 'MGRSCRIPT'
#!/bin/bash
# Xray Proxy Manager v4.1
# https://github.com/Evergreen05/xray-proxy-install

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
            PUBLIC_KEY=$(echo "$PUB_OUT" | grep -oE '[A-Za-z0-9+/]{42,45}={0,2}' | head -1)
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
    echo -e "${GREEN}节点1 (Reality+Fragment):${NC}  ${SERVER_IP}:443  [主力]"
    echo -e "${GREEN}节点2 (VLESS+TLS):${NC}        ${SERVER_IP}:8443 [备用]"
    echo -e "${GREEN}节点3 (XHTTP+TLS):${NC}       ${SERVER_IP}:8880 [CDN兼容]"
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

case "$1" in
    status)
        echo -e "${GREEN}=== Xray 服务状态 ===${NC}"
        if is_service_active xray; then echo "Xray: 运行中"; else echo "Xray: 未运行"; fi
        echo ""
        echo -e "${GREEN}=== Nginx 服务状态 ===${NC}"
        if is_service_active nginx; then echo "Nginx: 运行中"; else echo "Nginx: 未运行"; fi
        echo ""
        echo -e "${GREEN}=== 端口监听 ===${NC}"
        for port in 443 8443 8880; do
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
        if command -v systemctl &>/dev/null; then
            systemctl daemon-reload 2>/dev/null || true
        fi
        bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null || true
        sysctl --system >/dev/null 2>&1 || true
        echo -e "${GREEN}卸载完成${NC}"
        ;;
    *)
        echo -e "${BLUE}Xray Proxy Manager v4.1${NC}"
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
        echo "  uninstall - 卸载代理服务"
        ;;
esac
MGRSCRIPT

chmod +x /usr/local/bin/proxy-manager
add_rollback "rm -f /usr/local/bin/proxy-manager"

# ============================================
# 15. 防火墙放行与健康检查
# ============================================
step "防火墙放行与健康检查"

open_firewall_port() {
    local port=$1
    # ufw (Debian/Ubuntu)
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "$port/tcp" >/dev/null 2>&1 && log "ufw: 放行 ${port}"
    # firewalld (RHEL/CentOS/Fedora) - 不依赖 systemctl 检测
    elif command -v firewall-cmd &>/dev/null; then
        if systemctl is-active --quiet firewalld 2>/dev/null || rc-service firewalld status >/dev/null 2>&1 || service firewalld status >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 && log "firewalld: 放行 ${port}"
        fi
    # iptables (通用回退)
    elif command -v iptables &>/dev/null; then
        if iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            log "iptables: 端口 ${port} 已放行"
        elif iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            log "iptables: 放行 ${port}"
        fi
    fi
}

for port in 443 8443 8880 "$SUB_PORT"; do
    open_firewall_port "$port"
done

HEALTH_OK=1
is_service_active xray && log "Xray: 运行中" || { warn "Xray: 未运行"; HEALTH_OK=0; }
is_service_active nginx && log "Nginx: 运行中" || { warn "Nginx: 未运行"; HEALTH_OK=0; }
for port in 443 8443 8880; do
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

# ============================================
# 16. 输出部署结果
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
echo -e "${CYAN}========== 节点信息 ==========${NC}"
echo -e "${GREEN}节点1 (Reality+Fragment):${NC}  ${SERVER_IP}:443  [主力/推荐]"
echo -e "${GREEN}节点2 (VLESS+TLS):${NC}        ${SERVER_IP}:8443 [备用/自签证书]"
echo -e "${GREEN}节点3 (XHTTP+TLS):${NC}       ${SERVER_IP}:8880 [CDN兼容/自签证书]"
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
echo -e "${GREEN}proxy-manager status${NC}   - 查看服务状态"
echo -e "${GREEN}proxy-manager restart${NC}  - 重启服务"
echo -e "${GREEN}proxy-manager log${NC}      - 查看日志"
echo -e "${GREEN}proxy-manager uninstall${NC} - 卸载代理服务"
echo ""
echo -e "${CYAN}GitHub:${NC} https://github.com/Evergreen05/xray-proxy-install"
echo ""
echo -e "${RED}重要提醒:${NC}"
echo -e "1. 请在云服务器控制台安全组放行端口: ${YELLOW}443 8443 8880 ${SUB_PORT}${NC}"
echo -e "2. 请保存以上信息，用于配置客户端"
echo -e "3. 请勿将订阅链接分享给他人"
echo -e "4. 节点2/3 使用自签证书，客户端需启用 skip-cert-verify"
echo -e "5. 订阅链接为 HTTP 明文传输，建议在可信网络环境下载"
echo -e "${BLUE}============================================================${NC}"
