#!/bin/bash
# 自动检测并修复 CentOS7 网络问题 (增强版)
# 作者: ChatGPT

LOGFILE="/var/log/network_check.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo -e "\n===== $(date '+%F %T') 开始网络检测 ====="

# 1. 获取默认网卡
NETCARD=$(ip route | grep '^default' | awk '{print $5}')

if [ -z "$NETCARD" ]; then
    echo "❌ 未检测到默认网卡，请检查网络配置"
    exit 1
fi
echo "✅ 检测到默认网卡: $NETCARD"

# 2. 检查网卡是否启用
nmcli device status | grep -q "$NETCARD.*connected"
if [ $? -ne 0 ]; then
    echo "⚠️ 网卡 $NETCARD 未启动，正在尝试启动..."
    nmcli device connect "$NETCARD"
    sleep 3
fi

# 3. 检查是否有 IP 地址
IPADDR=$(ip addr show "$NETCARD" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "$IPADDR" ]; then
    echo "⚠️ 网卡 $NETCARD 未分配 IP，正在重启 network 服务..."
    systemctl restart network
    sleep 5
    IPADDR=$(ip addr show "$NETCARD" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    if [ -z "$IPADDR" ]; then
        echo "❌ 仍然没有分配到 IP，请检查 DHCP/静态配置"
        exit 1
    fi
fi
echo "✅ 网卡 $NETCARD IP 地址: $IPADDR"

# 4. 检查网关是否可达
GATEWAY=$(ip route | grep '^default' | awk '{print $3}')
if [ -z "$GATEWAY" ]; then
    echo "❌ 未检测到默认网关，请检查路由配置"
    exit 1
fi
echo "✅ 默认网关: $GATEWAY"

ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚠️ 网关 $GATEWAY 不可达，尝试修复..."
    systemctl restart network
    sleep 5
    ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 网关仍不可达，可能是宿主机网络或虚拟化配置问题"
        exit 1
    fi
fi
echo "✅ 网关可达"

# 5. 检查 DNS
check_dns() {
    DOMAIN=$1
    ping -c 2 -W 2 "$DOMAIN" >/dev/null 2>&1
    return $?
}

if ! check_dns "www.baidu.com"; then
    echo "⚠️ DNS 解析失败，尝试修复 resolv.conf 和 ifcfg 配置..."

    # 更新 /etc/resolv.conf
    cat > /etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
nameserver 8.8.8.8
EOF

    # 同时写入 ifcfg 配置，避免被 NetworkManager 覆盖
    IFCFG_FILE="/etc/sysconfig/network-scripts/ifcfg-$NETCARD"
    sed -i '/^DNS[0-9]*=/d' "$IFCFG_FILE"
    echo "DNS1=223.5.5.5" >> "$IFCFG_FILE"
    echo "DNS2=223.6.6.6" >> "$IFCFG_FILE"
    echo "DNS3=8.8.8.8" >> "$IFCFG_FILE"

    systemctl restart NetworkManager
    sleep 5
fi

# 6. 最终验证
if check_dns "www.baidu.com"; then
    echo "🎉 网络修复完成，可以正常访问互联网"
else
    echo "❌ DNS 修复失败，请检查宿主机是否能访问外网 (可能是桥接/NAT 设置问题)"
fi

echo "===== 网络检测结束 ====="

