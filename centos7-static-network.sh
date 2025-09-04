#!/bin/bash

# CentOS 7 静态网络配置脚本
# 支持自定义 IP、网关和 DNS

set -e  # 遇到任何错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 默认网络配置
DEFAULT_IP="192.168.66.150"
DEFAULT_NETMASK="255.255.255.0"
DEFAULT_GATEWAY="192.168.66.1"
DEFAULT_DNS1="8.8.8.8"
DEFAULT_DNS2="8.8.4.4"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 检测网络接口
detect_interface() {
    log_info "检测网络接口..."
    
    # 获取已连接的网络接口
    interfaces=$(ip link show | grep -E "^[0-9]+:" | grep -E "state UP|UNKNOWN" | awk -F': ' '{print $2}' | grep -v lo)
    
    if [[ -z "$interfaces" ]]; then
        log_error "未找到活动的网络接口"
        exit 1
    fi
    
    # 显示可用接口
    log_info "可用的网络接口:"
    counter=1
    for iface in $interfaces; do
        echo "$counter) $iface"
        counter=$((counter+1))
    done
    
    # 让用户选择接口
    read -p "请选择要配置的网络接口 (输入数字): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $(echo $interfaces | wc -w) ]; then
        log_error "无效的选择"
        exit 1
    fi
    
    # 获取选择的接口
    INTERFACE=$(echo $interfaces | cut -d ' ' -f $choice)
    log_info "选择的网络接口: $INTERFACE"
}

# 获取网络配置信息
get_network_config() {
    log_info "请输入网络配置信息 (直接回车使用默认值)"
    
    read -p "IP 地址 [默认: $DEFAULT_IP]: " IP
    IP=${IP:-$DEFAULT_IP}
    
    read -p "子网掩码 [默认: $DEFAULT_NETMASK]: " NETMASK
    NETMASK=${NETMASK:-$DEFAULT_NETMASK}
    
    read -p "网关 [默认: $DEFAULT_GATEWAY]: " GATEWAY
    GATEWAY=${GATEWAY:-$DEFAULT_GATEWAY}
    
    read -p "首选 DNS [默认: $DEFAULT_DNS1]: " DNS1
    DNS1=${DNS1:-$DEFAULT_DNS1}
    
    read -p "备用 DNS [默认: $DEFAULT_DNS2]: " DNS2
    DNS2=${DNS2:-$DEFAULT_DNS2}
    
    # 显示配置摘要
    echo
    log_info "网络配置摘要:"
    echo "接口: $INTERFACE"
    echo "IP 地址: $IP"
    echo "子网掩码: $NETMASK"
    echo "网关: $GATEWAY"
    echo "DNS: $DNS1, $DNS2"
    echo
    
    read -p "确认配置是否正确? (y/N): " confirm
    if [[ ! "$confirm" =~ [Yy] ]]; then
        log_info "已取消操作"
        exit 0
    fi
}

# 检查现有的网络配置
check_existing_config() {
    log_info "检查现有的网络配置..."
    
    # 检查是否已有配置文件
    if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE" ]]; then
        log_warning "发现现有的网络配置"
        read -p "是否要备份现有配置? (y/N): " choice
        if [[ "$choice" =~ [Yy] ]]; then
            cp "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE" "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE.bak"
            log_info "已备份现有配置"
        fi
    fi
}

# 配置静态IP
configure_static_ip() {
    log_info "配置静态网络..."
    
    # 创建网络配置文件
    cat > "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE" << EOF
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=$INTERFACE
DEVICE=$INTERFACE
ONBOOT=yes
IPADDR=$IP
NETMASK=$NETMASK
GATEWAY=$GATEWAY
DNS1=$DNS1
DNS2=$DNS2
EOF
    
    # 重启网络服务
    systemctl restart network
    
    log_info "静态网络配置已完成"
}

# 测试网络连接
test_network() {
    log_info "测试网络连接..."
    
    # 等待一会儿让网络配置生效
    sleep 3
    
    # 测试网关连接
    if ping -c 3 -W 2 $GATEWAY &> /dev/null; then
        log_info "网关连接成功"
    else
        log_warning "无法连接到网关，请检查网络配置"
    fi
    
    # 测试外部连接
    if ping -c 3 -W 2 8.8.8.8 &> /dev/null; then
        log_info "外部网络连接成功"
    else
        log_warning "无法连接到外部网络，DNS 可能有问题"
    fi
    
    # 显示当前IP配置
    log_info "当前网络配置:"
    ip addr show dev $INTERFACE
    echo
    log_info "路由信息:"
    ip route show
    echo
    log_info "DNS 配置:"
    cat /etc/resolv.conf
}

# 主函数
main() {
    log_info "开始配置 CentOS 7 静态网络"
    check_root
    detect_interface
    get_network_config
    check_existing_config
    configure_static_ip
    test_network
    log_info "静态网络配置完成！当前 IP: $IP"
}

# 执行主函数
main "$@"
