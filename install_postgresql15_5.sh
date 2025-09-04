#!/bin/bash

# PostgreSQL 15 安装脚本 (CentOS/RHEL 7)
# 修复 libpq.so.5 和 libzstd.so.1 依赖问题
# 作者: 系统管理员
# 版本: 1.4

# 错误时退出
set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "✗ 此脚本必须以 root 身份运行。请尝试: sudo $0"
    exit 1
fi

# 配置参数
PG_VERSION="15"
PG_SERVICE="postgresql-${PG_VERSION}"
PG_DATA_DIR="/var/lib/pgsql/${PG_VERSION}/data"
RPM_VERSION="15.5"

# 修复 libzstd 依赖问题
ensure_libzstd() {
    echo "确保 libzstd.so.1 可用..."
    
    # 检查是否已安装 libzstd
    if rpm -q libzstd >/dev/null 2>&1; then
        echo "✓ libzstd 已安装"
        return 0
    fi
    
    echo "安装 EPEL 仓库和 libzstd..."
    yum install -y epel-release
    yum install -y libzstd
    
    # 验证安装
    if rpm -q libzstd >/dev/null 2>&1; then
        echo "✓ libzstd 安装成功"
        return 0
    else
        echo "✗ libzstd 安装失败"
        return 1
    fi
}

# 修复 libpq 依赖问题
fix_libpq_dependency() {
    echo "修复 libpq 依赖问题..."
    
    # 检查 libpq.so.5 是否存在
    if [ -f /usr/pgsql-${PG_VERSION}/lib/libpq.so.5 ]; then
        echo "ℹ libpq.so.5 已存在于 PostgreSQL 安装目录"
    else
        echo "✗ /usr/pgsql-${PG_VERSION}/lib/libpq.so.5 缺失"
        return 1
    fi
    
    # 检查系统库目录中的链接
    if [ -f /usr/lib64/libpq.so.5 ]; then
        echo "✓ /usr/lib64/libpq.so.5 已存在"
        return 0
    fi
    
    echo "创建 libpq.so.5 符号链接..."
    
    # 创建符号链接
    ln -sf /usr/pgsql-${PG_VERSION}/lib/libpq.so.5 /usr/lib64/libpq.so.5
    
    # 更新动态链接器缓存
    ldconfig
    
    # 验证修复
    if [ -f /usr/lib64/libpq.so.5 ]; then
        echo "✓ 已成功创建符号链接: /usr/lib64/libpq.so.5"
        return 0
    else
        echo "✗ 无法创建符号链接"
        return 1
    fi
}

# 安装 PostgreSQL
install_postgresql() {
    echo "安装 PostgreSQL ${PG_VERSION}..."
    
    # 如果已安装则跳过
    if rpm -q "postgresql${PG_VERSION}-server" >/dev/null 2>&1; then
        echo "ℹ PostgreSQL ${PG_VERSION} 已安装"
        return 0
    fi
    
    # 安装基础依赖
    yum install -y libicu
    
    # 下载并安装 RPM 包
    RPM_URLS=(
        "https://download.postgresql.org/pub/repos/yum/${PG_VERSION}/redhat/rhel-7.12-x86_64/postgresql${PG_VERSION}-libs-${RPM_VERSION}-1PGDG.rhel7.x86_64.rpm"
        "https://download.postgresql.org/pub/repos/yum/${PG_VERSION}/redhat/rhel-7.12-x86_64/postgresql${PG_VERSION}-${RPM_VERSION}-1PGDG.rhel7.x86_64.rpm"
        "https://download.postgresql.org/pub/repos/yum/${PG_VERSION}/redhat/rhel-7.12-x86_64/postgresql${PG_VERSION}-server-${RPM_VERSION}-1PGDG.rhel7.x86_64.rpm"
    )
    
    # 清理可能存在的旧包
    rm -f /tmp/postgresql*.rpm
    
    for url in "${RPM_URLS[@]}"; do
        rpm_name=$(basename "$url")
        echo "下载: $rpm_name"
        
        # 下载 RPM
        if ! curl -s -o "/tmp/$rpm_name" "$url"; then
            echo "✗ 下载失败: $url"
            return 1
        fi
        
        # 安装 RPM
        if rpm -Uvh --force "/tmp/$rpm_name" >/dev/null 2>&1; then
            echo "✓ 安装成功"
        else
            # 尝试使用 yum 安装解决依赖
            if yum install -y "/tmp/$rpm_name" >/dev/null 2>&1; then
                echo "✓ 使用 yum 安装成功"
            else
                echo "✗ 安装失败: $rpm_name"
                return 1
            fi
        fi
        
        # 清理
        rm -f "/tmp/$rpm_name"
    done
    
    # 验证安装
    if rpm -q "postgresql${PG_VERSION}-server" >/dev/null 2>&1; then
        echo "✓ PostgreSQL ${PG_VERSION} 安装成功"
        return 0
    else
        echo "✗ PostgreSQL ${PG_VERSION} 安装失败"
        return 1
    fi
}

# 初始化数据库
initialize_database() {
    echo "初始化 PostgreSQL 数据库..."
    
    # 确保目录存在
    mkdir -p "$PG_DATA_DIR"
    chown postgres:postgres "$PG_DATA_DIR"
    chmod 700 "$PG_DATA_DIR"
    
    # 检查库依赖
    echo "=== 检查 PostgreSQL 依赖库 ==="
    ldd /usr/pgsql-${PG_VERSION}/bin/initdb
    
    # 初始化数据库（避免在 /root 目录运行）
    cd /tmp
    if sudo -u postgres /usr/pgsql-${PG_VERSION}/bin/initdb -D "$PG_DATA_DIR"; then
        cd - >/dev/null
        echo "✓ 数据库初始化成功"
        return 0
    else
        cd - >/dev/null
        echo "✗ 初始化失败，尝试备用方法..."
        
        # 备用方法：使用绝对路径初始化
        cd /tmp
        if /usr/pgsql-${PG_VERSION}/bin/initdb -D "$PG_DATA_DIR" -U postgres; then
            cd - >/dev/null
            echo "✓ 备用方法初始化成功"
            return 0
        else
            cd - >/dev/null
            echo "✗ 所有初始化方法均失败"
            return 1
        fi
    fi
}

# 启动服务
start_service() {
    echo "配置并启动 PostgreSQL 服务..."
    
    # 启用服务
    systemctl enable $PG_SERVICE >/dev/null 2>&1
    
    # 启动服务
    if systemctl start $PG_SERVICE >/dev/null 2>&1; then
        # 检查服务状态
        if systemctl is-active --quiet $PG_SERVICE; then
            echo "✓ PostgreSQL 服务正在运行"
            return 0
        fi
    fi
    
    echo "⚠ 无法通过 systemd 启动服务，尝试手动启动..."
    
    # 手动启动
    if sudo -u postgres /usr/pgsql-${PG_VERSION}/bin/pg_ctl -D "$PG_DATA_DIR" -l "$PG_DATA_DIR/startup.log" start; then
        echo "✓ 手动启动成功"
        return 0
    else
        echo "✗ 手动启动失败"
        echo "=== 日志内容 ==="
        tail -n 20 "$PG_DATA_DIR/startup.log" || echo "无日志文件"
        return 1
    fi
}

# 安装后配置
post_install_setup() {
    echo "执行安装后配置..."
    
    # 设置 postgres 用户密码
    if sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'PostgresAdmin@123';" >/dev/null 2>&1; then
        echo "✓ 已设置 postgres 用户密码为: PostgresAdmin@123"
    else
        echo "⚠ 无法设置密码。请手动运行:"
        echo "   sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'your-password';\""
    fi
    
    # 配置防火墙
    if firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=5432/tcp >/dev/null
        firewall-cmd --reload >/dev/null
        echo "✓ 已为 PostgreSQL 端口 5432 配置防火墙"
    fi
    
    # 获取连接信息
    PG_PORT="5432"
    if [ -f "$PG_DATA_DIR/postgresql.conf" ]; then
        conf_port=$(grep 'port =' "$PG_DATA_DIR/postgresql.conf" | awk '{print $3}')
        [ -n "$conf_port" ] && PG_PORT="$conf_port"
    fi
    
    # 打印成功信息
    echo ""
    echo "======================================================="
    echo " PostgreSQL ${PG_VERSION}-${RPM_VERSION} 安装完成！ "
    echo "======================================================="
    echo " 服务状态:   $(systemctl is-active ${PG_SERVICE} 2>/dev/null || echo '手动启动')"
    echo " 数据目录:   ${PG_DATA_DIR}"
    echo " 端口号:     ${PG_PORT}"
    echo " 版本:       PostgreSQL ${PG_VERSION}.${RPM_VERSION}"
    echo ""
    echo " 连接命令:"
    echo " sudo -u postgres psql"
    echo " psql -h localhost -U postgres -p ${PG_PORT}"
    echo ""
    echo " 重要提示:"
    echo " 1. 为 'postgres' 用户设置密码:"
    echo "    sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'your-password';\""
    echo " 2. 配置文件位置: ${PG_DATA_DIR}/postgresql.conf"
    echo " 3. 日志文件位置: ${PG_DATA_DIR}/startup.log"
    echo " 4. libpq.so.5 位置: /usr/pgsql-${PG_VERSION}/lib/libpq.so.5"
    echo "======================================================="
}

# 主安装流程
{
    echo "开始安装 PostgreSQL ${PG_VERSION}-${RPM_VERSION}..."
    echo "======================================================="
    
    # 步骤 0: 确保 libzstd 依赖
    ensure_libzstd || {
        echo "✗ 无法解决 libzstd 依赖问题"
        exit 1
    }
    
    # 步骤 1: 安装 PostgreSQL
    install_postgresql || exit 1
    
    # 步骤 2: 修复 libpq 依赖
    fix_libpq_dependency || {
        echo "✗ 无法修复 libpq 依赖问题"
        exit 1
    }
    
    # 步骤 3: 初始化数据库
    initialize_database || exit 1
    
    # 步骤 4: 启动服务
    start_service || exit 1
    
    # 步骤 5: 安装后配置
    post_install_setup
    
    echo "✓ PostgreSQL ${PG_VERSION}-${RPM_VERSION} 安装于 $(date) 成功完成！"
    exit 0
    
} || {
    echo "✗ 安装在上一步失败"
    exit 1
}