#!/bin/bash
# =========================================
# 通用系统初始化脚本（CentOS7/8/9）
# =========================================

set -e

echo "===== 1. 检测主网卡 ====="
NIC=$(ip route | grep '^default' | awk '{print $5}')
echo "检测到主网卡: $NIC"

read -p "请输入固定IP地址: " IP_ADDR
read -p "请输入子网掩码 (例如 255.255.255.0): " NETMASK
read -p "请输入网关: " GATEWAY
read -p "请输入首选DNS: " DNS1

echo "备份原网络配置..."
mkdir -p /etc/sysconfig/network-scripts/backup/
cp /etc/sysconfig/network-scripts/ifcfg-$NIC /etc/sysconfig/network-scripts/backup/ 2>/dev/null || true

cat > /etc/sysconfig/network-scripts/ifcfg-$NIC <<EOF
TYPE=Ethernet
BOOTPROTO=static
NAME=$NIC
DEVICE=$NIC
ONBOOT=yes
IPADDR=$IP_ADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
DNS1=$DNS1
EOF

if systemctl is-active --quiet NetworkManager; then
    systemctl restart NetworkManager
else
    systemctl restart network
fi
echo "固定IP配置完成：$IP_ADDR"

echo "===== 2. 替换 YUM 源 ====="
mkdir -p /etc/yum.repos.d/backup
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/
OS_VER=$(rpm -E %{rhel})
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-${OS_VER}.repo
yum clean all
yum makecache

echo "===== 3. 安装常用软件包 ====="
yum install -y vim-enhanced net-tools psmisc wget unzip ntpdate bzip2 tree bash-completion

echo "===== 4. 关闭 SELinux ====="
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
setenforce 0 || true

echo "===== 5. 关闭防火墙 ====="
if systemctl is-active --quiet firewalld; then
    systemctl stop firewalld
fi
systemctl disable firewalld
systemctl mask firewalld
iptables -F || true

echo "===== 6. 时间同步 ====="
ntpdate time.windows.com
hwclock --systohc

echo "===== 7. 配置命令提示符 (PS1) ====="
cat >> ~/.bashrc <<'EOF'

# 自定义命令提示符
export PS1='\[\e[0;31m\]┌─\[\e[1;32m\][\[\e[1m\]\[\e[3;35m\]\u\[\e[0m\]@\[\e[1;33m\]\H\[\e[1;32m\]][\[\e[1;34m\]\t\[\e[1;32m\]] \[\e[1;30m\]\[\e[3;30m\]$PWD\[\e[0m\]\n\[\e[0;31m\]└──╼ \[\e[0m\]\\$ '
EOF

# 立即生效
source ~/.bashrc

echo "===== 系统初始化完成 ====="
