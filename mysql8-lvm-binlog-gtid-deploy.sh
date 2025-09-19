#!/bin/bash
# 自动化部署 MySQL 8.0（EL7系）- 带LVM、binlog独立挂载、GTID、用户与备份
# 强警告：将对 $MYSQL_DATA_LV / $MYSQL_BINLOG_LV 执行 pvcreate/vgcreate/lvcreate（破坏性）
# 运行前请确认：root权限、YUM可用、磁盘无重要数据、网络与时间同步、主机名等

set -euo pipefail

# -----------------------------
# 配置参数
# -----------------------------
MYSQL_ROOT_PASSWORD='Root123!'
MYSQL_USER='proxyuser'
MYSQL_PASS='WWW.1.com'
MYSQL_DB='blog'

# 物理盘/分区（将被LVM使用，危险操作）
MYSQL_DATA_LV='/dev/sdb'       # ext4 数据目录逻辑卷磁盘
MYSQL_BINLOG_LV='/dev/sdc'     # xfs 二进制日志磁盘

# 挂载点
MYSQL_DATA_MOUNT='/var/lib/mysql'
MYSQL_BINLOG_MOUNT='/var/lib/mysql-binlog'

# 其他
MYSQL_PORT=3306
SERVER_ID=1

# -----------------------------
# 工具函数
# -----------------------------
need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 运行."; exit 1
  fi
}

ensure_cmds() {
  for c in yum systemctl awk sed grep rsync mkfs.xfs mkfs.ext4 pvcreate vgcreate lvcreate lsblk; do
    command -v "$c" >/dev/null 2>&1 || { echo "缺少命令: $c"; exit 1; }
  done
}

confirm_device() {
  local dev="$1"
  if [[ ! -b "$dev" ]]; then
    echo "设备不存在或不是块设备: $dev"; exit 1
  fi
}

fstab_has() {
  local entry="$1"
  grep -qsF "$entry" /etc/fstab
}

selinux_enforcing() {
  if command -v getenforce >/dev/null 2>&1; then
    [[ "$(getenforce)" == "Enforcing" ]]
  else
    return 1
  fi
}

# -----------------------------
# 1. 配置LVM与挂载（先做，避免数据目录被后挂载遮蔽）
# -----------------------------
setup_lvm() {
  echo "[1] 配置 LVM 与挂载..."
  confirm_device "$MYSQL_DATA_LV"
  confirm_device "$MYSQL_BINLOG_LV"

  # 数据盘
  if ! pvs | grep -q " $MYSQL_DATA_LV"; then
    pvcreate -ff -y "$MYSQL_DATA_LV"
  fi
  if ! vgs | grep -q "^vg_mysql"; then
    vgcreate vg_mysql "$MYSQL_DATA_LV"
  fi
  if ! lvs | grep -q "^lv_data"; then
    lvcreate -l 100%FREE -n lv_data vg_mysql
  fi
  if ! blkid /dev/vg_mysql/lv_data >/dev/null 2>&1; then
    mkfs.ext4 -F /dev/vg_mysql/lv_data
  fi
  mkdir -p "$MYSQL_DATA_MOUNT"
  if ! mountpoint -q "$MYSQL_DATA_MOUNT"; then
    mount /dev/vg_mysql/lv_data "$MYSQL_DATA_MOUNT"
  fi
  local data_fstab="/dev/vg_mysql/lv_data $MYSQL_DATA_MOUNT ext4 defaults 0 0"
  fstab_has "$data_fstab" || echo "$data_fstab" >> /etc/fstab

  # binlog盘
  if ! pvs | grep -q " $MYSQL_BINLOG_LV"; then
    pvcreate -ff -y "$MYSQL_BINLOG_LV"
  fi
  if ! vgs | grep -q "^vg_binlog"; then
    vgcreate vg_binlog "$MYSQL_BINLOG_LV"
  fi
  if ! lvs | grep -q "^lv_binlog"; then
    lvcreate -l 100%FREE -n lv_binlog vg_binlog
  fi
  if ! blkid /dev/vg_binlog/lv_binlog >/dev/null 2>&1; then
    mkfs.xfs -f /dev/vg_binlog/lv_binlog
  fi
  mkdir -p "$MYSQL_BINLOG_MOUNT"
  if ! mountpoint -q "$MYSQL_BINLOG_MOUNT"; then
    mount /dev/vg_binlog/lv_binlog "$MYSQL_BINLOG_MOUNT"
  fi
  local binlog_fstab="/dev/vg_binlog/lv_binlog $MYSQL_BINLOG_MOUNT xfs defaults 0 0"
  fstab_has "$binlog_fstab" || echo "$binlog_fstab" >> /etc/fstab

  # 预创建权限
  mkdir -p "$MYSQL_DATA_MOUNT" "$MYSQL_BINLOG_MOUNT"
  chown -R mysql:mysql "$MYSQL_DATA_MOUNT" 2>/dev/null || true
  chown -R mysql:mysql "$MYSQL_BINLOG_MOUNT" 2>/dev/null || true
}

# -----------------------------
# 2. 安装 MySQL
# -----------------------------
install_mysql() {
  echo "[2] 安装 MySQL..."
  yum install -y https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm
  yum install -y mysql-community-server
  systemctl enable mysqld
}

# -----------------------------
# 3. 配置 my.cnf（首次启动前写好）
# -----------------------------
configure_mysql() {
  echo "[3] 写入 /etc/my.cnf ..."
  cat > /etc/my.cnf <<EOF
[client]
port=$MYSQL_PORT
socket=$MYSQL_DATA_MOUNT/mysql.sock

[mysqld]
user=mysql
port=$MYSQL_PORT
datadir=$MYSQL_DATA_MOUNT
socket=$MYSQL_DATA_MOUNT/mysql.sock
pid-file=/var/run/mysqld/mysqld.pid
log-error=/var/log/mysqld.log
symbolic-links=0

# 二进制日志
server-id=$SERVER_ID
log_bin=$MYSQL_BINLOG_MOUNT/mysql-bin
binlog_format=ROW
gtid_mode=ON
enforce_gtid_consistency=ON
binlog_expire_logs_seconds=604800

# 慢查询
slow_query_log=ON
slow_query_log_file=/var/log/mysql-slow.log
long_query_time=1

# 推荐
innodb_flush_log_at_trx_commit=1
sync_binlog=1
EOF

  # 目录与权限
  mkdir -p "$MYSQL_DATA_MOUNT" "$MYSQL_BINLOG_MOUNT" /var/run/mysqld
  chown -R mysql:mysql "$MYSQL_DATA_MOUNT" "$MYSQL_BINLOG_MOUNT" /var/run/mysqld
  chmod 750 "$MYSQL_DATA_MOUNT" || true

  # SELinux（如启用）
  if selinux_enforcing; then
    command -v semanage >/dev/null 2>&1 || yum install -y policycoreutils-python
    semanage fcontext -a -t mysqld_db_t "$MYSQL_DATA_MOUNT(/.*)?"
    semanage fcontext -a -t mysqld_log_t "$MYSQL_BINLOG_MOUNT(/.*)?"
    restorecon -Rv "$MYSQL_DATA_MOUNT" "$MYSQL_BINLOG_MOUNT" || true
  fi
}

# -----------------------------
# 4. 启动并设置 root 密码
# -----------------------------
init_and_secure_mysql() {
  echo "[4] 启动 MySQL 并设置 root 密码..."
  systemctl restart mysqld

  # 等待日志落盘
  sleep 3
  local TEMP_PASS=""
  TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log | tail -1 | awk '{print $NF}') || true
  if [[ -z "${TEMP_PASS:-}" ]]; then
    echo "未找到临时密码，等待并重试一次..."
    sleep 2
    TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log | tail -1 | awk '{print $NF}') || true
  fi
  if [[ -z "${TEMP_PASS:-}" ]]; then
    echo "获取临时密码失败，退出。"; journalctl -u mysqld --no-pager | tail -200; exit 1
  fi
  echo "MySQL 临时密码: $TEMP_PASS"

  mysql --connect-expired-password -uroot -p"$TEMP_PASS" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
UNINSTALL COMPONENT 'file://component_validate_password' /* 如果启用了密码插件可按需关闭 */;
SQL
}

# -----------------------------
# 5. 创建数据库与用户
# -----------------------------
create_db_user() {
  echo "[5] 创建数据库和业务用户..."
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';"
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'%'; FLUSH PRIVILEGES;"
}

# -----------------------------
# 6. 配置复制账号（主库侧）
# -----------------------------
setup_gtid_replication() {
  echo "[6] 创建复制账号（主库）..."
  local SLAVE_USER='replica'
  local SLAVE_PASS='replica123'
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '${SLAVE_USER}'@'%' IDENTIFIED BY '${SLAVE_PASS}';"
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT REPLICATION SLAVE ON *.* TO '${SLAVE_USER}'@'%'; FLUSH PRIVILEGES;"

  echo "在从库上执行（示例，需替换主库IP）："
  echo "CHANGE REPLICATION SOURCE TO SOURCE_HOST='主库IP', SOURCE_USER='${SLAVE_USER}', SOURCE_PASSWORD='${SLAVE_PASS}', SOURCE_AUTO_POSITION=1;"
  echo "START REPLICA;"
}

# -----------------------------
# 7. 备份（逻辑备份）
# -----------------------------
backup_database() {
  echo "[7] 逻辑备份..."
  local BACKUP_DIR="/backup/mysql"
  mkdir -p "$BACKUP_DIR"
  mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases --single-transaction --routines --triggers --events --master-data=2 > "$BACKUP_DIR/all_databases.sql"
  echo "备份完成: $BACKUP_DIR/all_databases.sql"
}

# -----------------------------
# 8. 防火墙
# -----------------------------
open_firewall() {
  if systemctl is-active --quiet firewalld; then
    echo "[8] 开放防火墙端口 $MYSQL_PORT ..."
    firewall-cmd --permanent --add-port=${MYSQL_PORT}/tcp || true
    firewall-cmd --reload || true
  fi
}

# -----------------------------
# 主流程
# -----------------------------
main() {
  need_root
  ensure_cmds

  setup_lvm
  install_mysql
  configure_mysql
  init_and_secure_mysql
  create_db_user
  setup_gtid_replication
  backup_database
  open_firewall

  echo "MySQL 自动部署完成！"
}
main
