#!/bin/bash

# WordPress数据库连接详细诊断脚本

# 配置参数
DB_HOST="192.168.66.143"
DB_USER="proxyuser"
DB_PASSWORD="your_password"  # 替换为实际密码
DB_NAME="blog"
MYSQL_PORT=3306

echo "=== WordPress数据库连接诊断 ==="
echo "目标主机: $DB_HOST"
echo "数据库名: $DB_NAME"
echo "用户名: $DB_USER"
echo ""

# 1. 检查网络连通性
echo "1. 检查网络连通性..."
if ping -c 3 -W 2 "$DB_HOST" >/dev/null 2>&1; then
    echo "✅ 网络连通性正常 - 主机 $DB_HOST 可访问"
else
    echo "❌ 网络连通性问题 - 无法访问主机 $DB_HOST"
    echo "   请检查:"
    echo "   - 主机IP地址是否正确"
    echo "   - 网络防火墙设置"
    echo "   - 主机是否在线"
    exit 1
fi

# 2. 检查MySQL端口是否开放
echo ""
echo "2. 检查MySQL端口($MYSQL_PORT)是否开放..."
if nc -z -w 2 "$DB_HOST" "$MYSQL_PORT" 2>/dev/null; then
    echo "✅ MySQL端口($MYSQL_PORT)已开放"
else
    echo "❌ MySQL端口($MYSQL_PORT)未开放或不可访问"
    echo "   可能的原因:"
    echo "   - MySQL服务未运行"
    echo "   - 防火墙阻止了端口访问"
    echo "   - MySQL配置绑定到了其他IP或端口"
    
    # 尝试检查MySQL服务状态（如果目标主机是本地）
    if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ]; then
        echo ""
        echo "检查本地MySQL服务状态..."
        if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null; then
            echo "✅ MySQL服务正在运行"
        else
            echo "❌ MySQL服务未运行"
            echo "   尝试启动MySQL服务: sudo systemctl start mysql"
        fi
    fi
    exit 1
fi

# 3. 尝试连接数据库（使用更安全的方式）
echo ""
echo "3. 尝试连接数据库..."
# 使用配置文件避免命令行密码警告
TMP_CNF=$(mktemp)
cat > "$TMP_CNF" << EOF
[client]
host = $DB_HOST
user = $DB_USER
password = $DB_PASSWORD
port = $MYSQL_PORT
EOF

if mysql --defaults-file="$TMP_CNF" -e "USE $DB_NAME; SELECT 1;" 2>/dev/null; then
    echo "✅ 数据库连接成功!"
    
    # 检查数据库和表
    echo ""
    echo "4. 检查数据库内容..."
    TABLE_COUNT=$(mysql --defaults-file="$TMP_CNF" -e "USE $DB_NAME; SHOW TABLES LIKE 'wp_%';" 2>/dev/null | wc -l)
    if [ "$TABLE_COUNT" -gt 0 ]; then
        echo "✅ WordPress表存在 ($TABLE_COUNT 个表)"
        
        # 检查WordPress配置
        SITE_URL=$(mysql --defaults-file="$TMP_CNF" -e "USE $DB_NAME; SELECT option_value FROM wp_options WHERE option_name = 'siteurl' LIMIT 1;" 2>/dev/null | tail -1)
        echo "网站URL: $SITE_URL"
    else
        echo "⚠️  数据库 '$DB_NAME' 中未找到WordPress表"
        echo "   可能的原因:"
        echo "   - WordPress未正确安装"
        echo "   - 使用了不同的表前缀"
    fi
else
    echo "❌ 数据库连接失败!"
    ERROR_MSG=$(mysql --defaults-file="$TMP_CNF" -e "USE $DB_NAME; SELECT 1;" 2>&1)
    echo "错误详情: $ERROR_MSG"
    
    # 尝试连接但不指定数据库
    echo ""
    echo "尝试连接MySQL服务器(不指定数据库)..."
    if mysql --defaults-file="$TMP_CNF" -e "SELECT 1;" 2>/dev/null; then
        echo "✅ MySQL服务器连接成功，但无法访问数据库 '$DB_NAME'"
        echo "   可能的原因:"
        echo "   - 数据库 '$DB_NAME' 不存在"
        echo "   - 用户 '$DB_USER' 没有访问数据库的权限"
        
        # 检查数据库是否存在
        echo ""
        echo "检查数据库是否存在..."
        if mysql --defaults-file="$TMP_CNF" -e "SHOW DATABASES LIKE '$DB_NAME';" 2>/dev/null | grep -q "$DB_NAME"; then
            echo "✅ 数据库 '$DB_NAME' 存在"
            echo "   问题可能是用户权限不足"
        else
            echo "❌ 数据库 '$DB_NAME' 不存在"
            echo "   需要创建数据库: CREATE DATABASE $DB_NAME;"
        fi
    else
        echo "❌ MySQL服务器连接失败"
        echo "   可能的原因:"
        echo "   - 用户名或密码错误"
        echo "   - 用户 '$DB_USER' 没有从当前主机连接的权限"
    fi
fi

# 清理临时文件
rm -f "$TMP_CNF"

echo ""
echo "=== 诊断完成 ==="
