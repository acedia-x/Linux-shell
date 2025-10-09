#!/bin/bash
# Zabbix 8.x 一键部署示例脚本（RHEL/CentOS 8/9）

# 1. 系统时间同步（推荐 chrony）
dnf install -y chrony
systemctl enable --now chronyd
chronyc sources

# 2. 添加 EPEL 源
dnf install -y epel-release

# 3. 添加 Zabbix 仓库（8.0 LTS）
rpm -Uvh https://repo.zabbix.com/zabbix/8.0/rhel/$(rpm -E %{rhel})/x86_64/zabbix-release-8.0-1.el$(rpm -E %{rhel}).noarch.rpm
dnf clean all

# 4. 安装数据库与 Zabbix server/web/agent
dnf install -y mariadb-server zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-agent

# 5. 启动数据库并安全配置
systemctl enable --now mariadb
mysql_secure_installation

# 6. 创建 Zabbix 数据库与用户
mysql -uroot -p <<MYSQL_SCRIPT
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 7. 导入初始 schema
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -p zabbix

# 8. 配置 Zabbix server DB 连接
sed -i "s/# DBPassword=/DBPassword=StrongPassword123!/" /etc/zabbix/zabbix_server.conf

# 9. 配置 PHP 时区
sed -i "s@;date.timezone =@date.timezone = Asia/Shanghai@" /etc/php.ini

# 10. 启动服务
systemctl enable --now zabbix-server zabbix-agent httpd

# 11. 防火墙设置
firewall-cmd --permanent --add-port=10050/tcp
firewall-cmd --permanent --add-port=10051/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# 12. SELinux 临时允许 Zabbix 访问网络（可选）
setsebool -P httpd_can_network_connect on

# 13. 验证端口
ss -tunlp | egrep '10050|10051|:80|:443'

echo "Zabbix 8.x 安装完成，请访问 http://<server-ip>/zabbix/ 进行 Web 配置。"

