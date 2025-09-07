#!/bin/bash
# MySQL Backup Verification Script
# 文件名: mysql_backup_check.sh
# 用法: ./mysql_backup_check.sh [备份文件路径]

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志文件
LOG_FILE="/var/log/mysql_backup_check.log"

# 默认备份目录
BACKUP_DIR="/mysql_data"

# 如果有参数，使用参数作为备份目录
if [ $# -gt 0 ]; then
    BACKUP_DIR="$1"
fi

# 检查备份目录是否存在
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}错误: 备份目录 $BACKUP_DIR 不存在${NC}"
    exit 1
fi

# 记录日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 检查备份文件函数
check_backup_file() {
    local file="$1"
    local result=""
    
    log_message "检查备份文件: $file"
    
    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        echo -e "${RED}错误: 文件不存在${NC}"
        return 1
    fi
    
    # 检查文件大小
    local file_size=$(du -h "$file" | cut -f1)
    if [ "$(du -b "$file" | cut -f1)" -eq 0 ]; then
        echo -e "${RED}警告: 文件大小为 0 (空文件)${NC}"
        return 2
    fi
    
    echo "文件大小: $file_size"
    
    # 检查文件头部
    local header=$(head -n 5 "$file" | grep -i "MySQL dump\|Dump created")
    if [ -n "$header" ]; then
        echo -e "${GREEN}✓ 文件头部正常${NC}"
    else
        echo -e "${YELLOW}⚠ 文件头部可能有问题${NC}"
    fi
    
    # 检查文件尾部
    local footer=$(tail -n 5 "$file" | grep -i "Dump completed\|-- Dump completed")
    if [ -n "$footer" ]; then
        echo -e "${GREEN}✓ 文件尾部正常${NC}"
    else
        echo -e "${YELLOW}⚠ 文件尾部可能不完整${NC}"
    fi
    
    # 检查文件是否包含数据库结构
    local has_tables=$(grep -i "CREATE TABLE" "$file" | head -n 1)
    if [ -n "$has_tables" ]; then
        echo -e "${GREEN}✓ 包含数据库表结构${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到表结构信息${NC}"
    fi
    
    # 检查文件是否包含数据
    local has_data=$(grep -i "INSERT INTO" "$file" | head -n 1)
    if [ -n "$has_data" ]; then
        echo -e "${GREEN}✓ 包含数据插入语句${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到数据插入语句${NC}"
    fi
    
    return 0
}

# 验证备份内容函数
verify_backup_content() {
    local file="$1"
    
    log_message "验证备份内容: $file"
    
    # 创建测试数据库
    local test_db="backup_test_$(date +%Y%m%d_%H%M%S)"
    mysql -u root -p -e "CREATE DATABASE $test_db" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 无法创建测试数据库，可能需要MySQL root密码${NC}"
        return 1
    fi
    
    # 尝试恢复备份
    echo "正在恢复备份到测试数据库 $test_db..."
    mysql -u root -p "$test_db" < "$file" 2>/tmp/mysql_restore_error.log
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 备份恢复成功${NC}"
        
        # 检查恢复的数据库
        local table_count=$(mysql -u root -p -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$test_db'" 2>/dev/null)
        echo "恢复的表数量: $table_count"
        
        # 清理测试数据库
        mysql -u root -p -e "DROP DATABASE $test_db" 2>/dev/null
        return 0
    else
        echo -e "${RED}错误: 备份恢复失败${NC}"
        echo "错误信息:"
        cat /tmp/mysql_restore_error.log
        
        # 清理测试数据库
        mysql -u root -p -e "DROP DATABASE IF EXISTS $test_db" 2>/dev/null
        return 1
    fi
}

# 主函数
main() {
    log_message "开始检查备份文件"
    echo "备份目录: $BACKUP_DIR"
    echo ""
    
    # 查找所有SQL备份文件
    local backup_files=$(find "$BACKUP_DIR" -name "*.sql" -type f | sort -r)
    
    if [ -z "$backup_files" ]; then
        echo -e "${RED}未找到任何SQL备份文件${NC}"
        return 1
    fi
    
    # 检查每个备份文件
    for file in $backup_files; do
        echo "================================================"
        echo "检查文件: $(basename "$file")"
        echo "================================================"
        
        check_backup_file "$file"
        
        # 询问是否验证备份内容
        read -p "是否验证此备份文件内容? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            verify_backup_content "$file"
        fi
        
        echo ""
    done
    
    log_message "备份检查完成"
}

# 执行主函数
main "$@"
