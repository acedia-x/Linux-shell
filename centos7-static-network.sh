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

# 全局变量
INTERFACE=""
IP=""
NETMASK=""
GATEWAY=""
DNS1=""
DNS2=""
DISABLE_NM=0

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
        
        # 尝试启用所有接口
        log_info "尝试启用所有网络接口..."
        for iface in $(ls /sys/class/net | grep -v lo); do
            ip link set $iface up
        done
        
        # 再次检查
        interfaces=$(ip link show | grep -E "^[0-9]+:" | grep -E "state UP|UNKNOWN" | awk -F': ' '{print $2}' | grep -v lo)
        
        if [[ -z "$interfaces" ]]; then
            log_error "仍然未找到活动的网络接口，请检查网络连接"
            exit 1
        fi
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

# 检查是否禁用 NetworkManager
check_disable_nm() {
    read -p "是否要禁用 NetworkManager? (推荐: y) [y/N]: " disable_nm
    if [[ "$disable_nm" =~ [Yy] ]]; then
        DISABLE_NM=1
        log_info "停止并禁用 NetworkManager..."
        systemctl stop NetworkManager
        systemctl disable NetworkManager
    else
        DISABLE_NM=0
        log_info "将不会禁用 NetworkManager，确保其不会覆盖DNS设置..."
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
            backup_file="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE.bak.$(date +%Y%m%d%H%M%S)"
            cp "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE" "$backup_file"
            log_info "已备份现有配置到 $backup_file"
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
NM_CONTROLLED=no
EOF
    
    # 如果不禁用 NetworkManager，则配置其不覆盖 DNS
    if [[ $DISABLE_NM -eq 0 ]]; then
        log_info "配置 NetworkManager 不覆盖 DNS 设置..."
        mkdir -p /etc/NetworkManager/conf.d
        cat > /etc/NetworkManager/conf.d/dns.conf << EOF
[main]
dns=none
EOF
        systemctl restart NetworkManager
    fi
    
    # 重启网络服务
    log_info "重启网络服务..."
    if systemctl restart network; then
        log_info "网络服务重启成功"
    else
        log_error "网络服务重启失败，尝试使用传统方法重新配置网络..."
        
        # 使用ip命令手动配置网络
        ip addr flush dev $INTERFACE
        ip addr add $IP/24 dev $INTERFACE
        ip link set dev $INTERFACE up
        ip route add default via $GATEWAY dev $INTERFACE
        
        # 配置DNS
        echo "nameserver $DNS1" > /etc/resolv.conf
        echo "nameserver $DNS2" >> /etc/resolv.conf
        
        # 防止文件被覆盖
        chattr +i /etc/resolv.conf 2>/dev/null || true
    fi
    
    log_info "静态网络配置已完成"
}

# 测试网络连接
test_network() {
    log_info "测试网络连接..."
    
    # 等待网络配置生效
    log_info "等待网络配置生效..."
    sleep 5
    
    # 检查接口状态
    if ip link show dev $INTERFACE | grep -q "state UP"; then
        log_info "网络接口 $INTERFACE 已启用"
    else
        log_error "网络接口 $INTERFACE 未启用"
        return 1
    fi
    
    # 检查IP地址配置
    if ip addr show dev $INTERFACE | grep -q "$IP"; then
        log_info "IP地址配置正确: $IP"
    else
        log_error "IP地址配置不正确"
        return 1
    fi
    
    # 测试网关连接
    if ping -c 3 -W 2 $GATEWAY &> /dev/null; then
        log_info "网关连接成功: $GATEWAY"
    else
        log_warning "无法连接到网关: $GATEWAY"
        return 1
    fi
    
    # 测试外部连接
    if ping -c 3 -W 2 8.8.8.8 &> /dev/null; then
        log_info "外部网络连接成功"
    else
        log_warning "无法连接到外部网络，检查防火墙状态..."
        if systemctl is-active --quiet firewalld; then
            log_info "防火墙正在运行，可能是防火墙阻止了出站流量"
            log_info "您可以暂时关闭防火墙以测试：systemctl stop firewalld"
        else
            log_info "防火墙未运行，请检查网关设置"
        fi
        return 1
    fi
    
    # 测试DNS解析
    if nslookup google.com &> /dev/null; then
        log_info "DNS解析正常"
    else
        log_warning "DNS解析失败，检查DNS配置"
        return 1
    fi
    
    # 显示当前网络配置
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
    check_disable_nm
    check_existing_config
    configure_static_ip
    test_network
    log_info "静态网络配置完成！当前 IP: $IP"
}

# 执行主函数
main "$@"
