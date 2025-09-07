#!/bin/bash

# PostgreSQL 15 安装脚本 (CentOS/RHEL 7)
# 综合优化版 - 修复依赖问题并支持国内镜像
# 版本: 2.0

# 错误时退出
set -e

# 日志函数
log_error() {
    local message="$1"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a /var/log/postgresql-install.log >&2
}

log_info() {
    local message="$1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a /var/log/postgresql-install.log
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本必须以 root 身份运行。请尝试: sudo $0"
        exit 1
    fi
}

# 配置参数
PG_VERSION="15"
PG_SERVICE="postgresql-${PG_VERSION}"
PG_DATA_DIR="/var/lib/pgsql/${PG_VERSION}/data"
RPM_VERSION="15.5"
LOG_FILE="/var/log/postgresql-install.log"

# 初始化日志
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log_info "=== PostgreSQL 安装开始 ==="
}

# 获取CentOS具体版本号
get_centos_version() {
    local version=""
    if [ -f /etc/centos-release ]; then
        # 提取主版本号和小版本号
        version=$(grep -oP 'CentOS .*? \K\d+\.\d+\.\d+' /etc/centos-release 2>/dev/null || echo "")
        if [ -z "$version" ]; then
            version=$(grep -oP 'release \K[\d.]+' /etc/centos-release | cut -d. -f1-3)
        fi
    fi
    echo "${version:-7}"  # 默认值
}

# 国内镜像源列表（按优先级排序）
MIRROR_LIST=(
    "https://mirrors.aliyun.com"
    "https://mirrors.huaweicloud.com"
    "https://mirrors.tuna.tsinghua.edu.cn"
    "https://mirrors.ustc.edu.cn"
)

# 选择最佳镜像源
select_mirror() {
    log_info "检测最佳镜像源..."
    
    for mirror in "${MIRROR_LIST[@]}"; do
        if curl --connect-timeout 5 -s "${mirror}" >/dev/null; then
            log_info "使用镜像源: ${mirror}"
            SELECTED_MIRROR="${mirror}"
            return 0
        fi
        log_info "无法访问: ${mirror}"
    done
    
    log_info "所有镜像源均不可用，尝试直接连接官方源"
    SELECTED_MIRROR="https://download.postgresql.org/pub"
    return 1
}

# 配置镜像源
configure_mirrors() {
    log_info "配置镜像源..."
    
    # 备份原有repo文件
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
    
    # 配置基础源
    cat > /etc/yum.repos.d/CentOS-Base.repo <<-EOF
[base]
name=CentOS-\$releasever - Base
baseurl=${SELECTED_MIRROR}/centos/${CENTOS_VERSION}/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[updates]
name=CentOS-\$releasever - Updates
baseurl=${SELECTED_MIRROR}/centos/${CENTOS_VERSION}/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[extras]
name=CentOS-\$releasever - Extras
baseurl=${SELECTED_MIRROR}/centos/${CENTOS_VERSION}/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1
EOF

    # 配置EPEL源
    cat > /etc/yum.repos.d/epel.repo <<-EOF
[epel]
name=Extra Packages for Enterprise Linux 7 - \$basearch
baseurl=${SELECTED_MIRROR}/epel/7/\$basearch
failovermethod=priority
enabled=1
gpgcheck=0
EOF

    # 配置PostgreSQL源
    cat > /etc/yum.repos.d/pgdg.repo <<-EOF
[pgdg15]
name=PostgreSQL 15 for RHEL/CentOS 7 - \$basearch
baseurl=${SELECTED_MIRROR}/postgresql/repos/yum/15/redhat/rhel-7-\$basearch
enabled=1
gpgcheck=0
EOF

    # 清理缓存
    yum clean all
    rm -rf /var/cache/yum
    yum makecache
    
    log_info "镜像源配置完成"
}

# 修复 libzstd 依赖问题
ensure_libzstd() {
    log_info "确保 libzstd.so.1 可用..."
    
    if rpm -q libzstd >/dev/null 2>&1; then
        log_info "libzstd 已安装"
        return 0
    fi
    
    log_info "安装 libzstd..."
    if ! yum install -y libzstd; then
        log_error "libzstd 安装失败"
        return 1
    fi
    
    log_info "libzstd 安装成功"
    return 0
}

# 修复 libpq 依赖问题
fix_libpq_dependency() {
    log_info "修复 libpq 依赖问题..."
    
    if [ -f "/usr/pgsql-${PG_VERSION}/lib/libpq.so.5" ]; then
        log_info "libpq.so.5 已存在于 PostgreSQL 安装目录"
    else
        log_error "/usr/pgsql-${PG_VERSION}/lib/libpq.so.5 缺失"
        return 1
    fi
    
    if [ -f /usr/lib64/libpq.so.5 ]; then
        log_info "/usr/lib64/libpq.so.5 已存在"
        return 0
    fi
    
    log_info "创建 libpq.so.5 符号链接..."
    ln -sf "/usr/pgsql-${PG_VERSION}/lib/libpq.so.5" /usr/lib64/libpq.so.5
    ldconfig
    
    if [ -f /usr/lib64/libpq.so.5 ]; then
        log_info "已成功创建符号链接"
        return 0
    else
        log_error "无法创建符号链接"
        return 1
    fi
}

# 带重试的安装函数
install_with_retry() {
    local cmd=$1
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if $cmd; then
            return 0
        fi
        retry_count=$((retry_count+1))
        log_info "操作失败，尝试第 ${retry_count} 次重试..."
        sleep 5
    done
    
    log_error "操作失败，已达到最大重试次数"
    return 1
}

# 安装PostgreSQL
install_postgresql() {
    log_info "安装 PostgreSQL ${PG_VERSION}..."
    
    if rpm -q "postgresql${PG_VERSION}-server" >/dev/null 2>&1; then
        log_info "PostgreSQL ${PG_VERSION} 已安装"
        return 0
    fi
    
    # 安装基础依赖
    yum install -y libicu
    
    # 尝试通过yum安装
    if install_with_retry "yum install -y postgresql${PG_VERSION}-server postgresql${PG_VERSION}-contrib"; then
        log_info "PostgreSQL 安装成功"
        return 0
    fi
    
    log_info "Yum安装失败，尝试RPM直接安装..."
    
    # RPM包URL列表
    RPM_URLS=(
        "${SELECTED_MIRROR}/postgresql/repos/yum/${PG_VERSION}/redhat/rhel-7.12-x86_64/postgresql${PG_VERSION}-libs-${RPM_VERSION}-1PGDG.rhel7.x86_64.rpm"
        "${SELECTED_MIRROR}/postgresql/repos/yum/${PG_VERSION}/redhat/rhel-7.12-x86_64/postgresql${PG_VERSION}-${RPM_VERSION}-1PGDG.rhel7.x86_64.rpm"
        "${SELECTED_MIRROR}/postgresql/repos/yum/${PG_VERSION}/redhat/rhel-7.12-x86_64/postgresql${PG_VERSION}-server-${RPM_VERSION}-1PGDG.rhel7.x86_64.rpm"
    )
    
    for url in "${RPM_URLS[@]}"; do
        rpm_name=$(basename "${url}")
        log_info "下载: ${rpm_name}"
        
        if ! curl -s -o "/tmp/${rpm_name}" "${url}"; then
            log_error "下载失败: ${url}"
            return 1
        fi
        
        if ! rpm -Uvh --force "/tmp/${rpm_name}" >/dev/null 2>&1; then
            log_error "安装失败: ${rpm_name}"
            return 1
        fi
        
        rm -f "/tmp/${rpm_name}"
    done
    
    if rpm -q "postgresql${PG_VERSION}-server" >/dev/null 2>&1; then
        log_info "PostgreSQL 安装成功"
        return 0
    else
        log_error "PostgreSQL 安装失败"
        return 1
    fi
}

# 初始化数据库
initialize_database() {
    log_info "初始化 PostgreSQL 数据库..."
    
    mkdir -p "${PG_DATA_DIR}"
    chown postgres:postgres "${PG_DATA_DIR}"
    chmod 700 "${PG_DATA_DIR}"
    
    if [ -f "${PG_DATA_DIR}/PG_VERSION" ]; then
        log_info "数据库已初始化"
        return 0
    fi
    
    # 检查依赖库
    log_info "检查依赖库..."
    ldd "/usr/pgsql-${PG_VERSION}/bin/initdb"
    
    # 使用官方初始化脚本
    if "/usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup" initdb; then
        log_info "数据库初始化成功"
        return 0
    fi
    
    log_info "官方初始化失败，尝试手动初始化..."
    
    # 手动初始化
    if sudo -u postgres "/usr/pgsql-${PG_VERSION}/bin/initdb" -D "${PG_DATA_DIR}"; then
        log_info "手动初始化成功"
        return 0
    else
        log_error "所有初始化方法均失败"
        return 1
    fi
}

# 启动服务
start_service() {
    log_info "启动 PostgreSQL 服务..."
    
    systemctl enable "${PG_SERVICE}" >/dev/null 2>&1
    
    if systemctl start "${PG_SERVICE}" >/dev/null 2>&1; then
        if systemctl is-active --quiet "${PG_SERVICE}"; then
            log_info "服务启动成功"
            return 0
        fi
    fi
    
    log_info "systemd启动失败，尝试手动启动..."
    
    if sudo -u postgres "/usr/pgsql-${PG_VERSION}/bin/pg_ctl" -D "${PG_DATA_DIR}" -l "${PG_DATA_DIR}/startup.log" start; then
        log_info "手动启动成功"
        return 0
    else
        log_error "服务启动失败"
        echo "=== 错误日志 ==="
        tail -n 20 "${PG_DATA_DIR}/startup.log" 2>/dev/null || echo "无日志文件"
        return 1
    fi
}

# 安装后配置
post_install_setup() {
    log_info "执行安装后配置..."
    
    # 设置密码
    log_info "设置PostgreSQL用户密码..."
    if sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'PostgresAdmin@123';" >/dev/null 2>&1; then
        log_info "密码设置成功"
    else
        log_info "密码设置失败，请手动运行: sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'your-password';\""
    fi
    
    # 防火墙配置
    if firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=5432/tcp >/dev/null
        firewall-cmd --reload >/dev/null
    fi
    
    # 显示连接信息
    PG_PORT=$(grep 'port =' "${PG_DATA_DIR}/postgresql.conf" 2>/dev/null | awk '{print $3}' || echo "5432")
    
    cat <<-EOF

=======================================================
 PostgreSQL ${PG_VERSION} 安装完成！
=======================================================
 服务状态:   $(systemctl is-active ${PG_SERVICE} 2>/dev/null || echo '手动启动')
 数据目录:   ${PG_DATA_DIR}
 端口号:     ${PG_PORT}
 版本:       $(sudo -u postgres /usr/pgsql-${PG_VERSION}/bin/postgres --version 2>/dev/null)

 连接命令:
   sudo -u postgres psql
   psql -h localhost -U postgres -p ${PG_PORT}

 重要提示:
 1. 用户名:    postgres
 2. 默认密码: PostgresAdmin@123
 3. 配置文件: ${PG_DATA_DIR}/postgresql.conf
 4. 日志文件: ${PG_DATA_DIR}/startup.log
 5. 安装日志: ${LOG_FILE}
=======================================================
EOF
}

# 清理函数
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "安装过程失败，退出码: $exit_code"
    fi
    log_info "=== PostgreSQL 安装结束 ==="
    exit $exit_code
}

# 主安装流程
main() {
    trap cleanup EXIT INT TERM
    init_log
    check_root
    
    log_info "开始安装 PostgreSQL ${PG_VERSION}..."
    
    # 获取系统版本
    CENTOS_VERSION=$(get_centos_version)
    log_info "检测到系统版本: CentOS $CENTOS_VERSION"
    
    # 安装步骤
    select_mirror
    configure_mirrors
    ensure_libzstd
    install_postgresql
    fix_libpq_dependency
    initialize_database
    start_service
    post_install_setup
    
    log_info "PostgreSQL ${PG_VERSION} 安装完成"
    return 0
}

main "$@"
