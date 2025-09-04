#!/bin/bash

# RAID 配置脚本
# 支持 RAID 0, 1, 5, 6, 10 级别
# 作者: 系统管理员
# 版本: 1.0

set -e

# 全局变量
LOG_FILE="/var/log/raid_configurator.log"
CONFIG_BACKUP_DIR="/etc/raid_backups"
MDADM_CONF="/etc/mdadm.conf"
TMP_CONFIG="/tmp/raid_temp_config.txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 权限运行"
    fi
}

# 检查 mdadm 是否安装
check_mdadm() {
    if ! command -v mdadm &> /dev/null; then
        log_info "mdadm 未安装，正在安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y mdadm
        elif command -v yum &> /dev/null; then
            yum install -y mdadm
        elif command -v dnf &> /dev/null; then
            dnf install -y mdadm
        else
            log_error "无法确定包管理器，请手动安装 mdadm"
        fi
    fi
    log_info "mdadm 已安装"
}

# 获取可用磁盘列表
get_available_disks() {
    # 排除系统盘和已用于RAID的磁盘
    local system_disk=$(lsblk -o MOUNTPOINT,NAME -r | grep -E '/boot|/$' | head -1 | awk '{print $2}' | sed 's/[0-9]*$//')
    
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | grep -E '^[a-z]+[a-z]?[0-9]?' | grep -v "loop\|${system_disk}\|fd0" | while read -r line; do
        local disk=$(echo $line | awk '{print $1}')
        local mounted=$(echo $line | awk '{print $4}')
        local fstype=$(echo $line | awk '{print $5}')
        
        # 检查磁盘是否已挂载或已有文件系统
        if [[ -n "$mounted" || -n "$fstype" ]]; then
            echo "$disk [已使用] - $(echo $line | awk '{print $2}')"
        else
            echo "$disk [可用] - $(echo $line | awk '{print $2}')"
        fi
    done
}

# 选择 RAID 级别
select_raid_level() {
    echo -e "\n${BLUE}请选择 RAID 级别:${NC}"
    echo "1) RAID 0 - 条带化 (性能提升，无冗余)"
    echo "2) RAID 1 - 镜像 (数据冗余，性能略降)"
    echo "3) RAID 5 - 带奇偶校验的条带化 (平衡性能与冗余)"
    echo "4) RAID 6 - 双奇偶校验 (更高冗余)"
    echo "5) RAID 10 - 镜像+条带化 (高性能高冗余)"
    
    local choice
    read -p "输入选择 (1-5): " choice
    
    case $choice in
        1) echo "0" ;;
        2) echo "1" ;;
        3) echo "5" ;;
        4) echo "6" ;;
        5) echo "10" ;;
        *) 
            log_error "无效选择"
            select_raid_level
            ;;
    esac
}

# 选择磁盘设备
select_devices() {
    local raid_level=$1
    local min_disks=2
    
    case $raid_level in
        0) min_disks=2 ;;
        1) min_disks=2 ;;
        5) min_disks=3 ;;
        6) min_disks=4 ;;
        10) min_disks=4 ;;
    esac
    
    echo -e "\n${BLUE}可用磁盘列表:${NC}"
    get_available_disks
    
    echo -e "\n${YELLOW}警告: 选择磁盘将清除其上所有数据!${NC}"
    echo -e "RAID ${raid_level} 需要至少 ${min_disks} 个磁盘"
    
    local devices=()
    while true; do
        read -p "输入要使用的磁盘设备 (如 sdb, 输入 'done' 完成): " device
        
        if [[ "$device" == "done" ]]; then
            if [[ ${#devices[@]} -lt $min_disks ]]; then
                echo -e "${RED}错误: RAID ${raid_level} 需要至少 ${min_disks} 个磁盘${NC}"
                continue
            fi
            break
        fi
        
        # 验证设备是否存在
        if [[ ! -b "/dev/${device}" ]]; then
            echo -e "${RED}错误: 设备 /dev/${device} 不存在${NC}"
            continue
        fi
        
        # 检查设备是否已使用
        local mounted=$(lsblk -o NAME,MOUNTPOINT -r | grep "^${device}" | awk '{print $2}')
        local fstype=$(lsblk -o NAME,FSTYPE -r | grep "^${device}" | awk '{print $2}')
        
        if [[ -n "$mounted" || -n "$fstype" ]]; then
            echo -e "${RED}警告: 设备 /dev/${device} 似乎已被使用${NC}"
            read -p "仍然要继续吗? (y/N): " confirm
            if [[ ! "$confirm" =~ [Yy] ]]; then
                continue
            fi
        fi
        
        devices+=("/dev/${device}")
        echo "已选择设备: ${devices[@]}"
    done
    
    echo "${devices[@]}"
}

# 配置高级选项
configure_advanced() {
    local options=""
    
    echo -e "\n${BLUE}高级配置选项:${NC}"
    
    # 块大小
    read -p "块大小 (默认: 512K, 可选: 4K, 16K, 32K, 64K, 128K, 256K, 512K, 1M): " chunk_size
    if [[ -n "$chunk_size" ]]; then
        options+="--chunk=${chunk_size} "
    fi
    
    # 备用设备
    read -p "是否添加备用设备? (y/N): " add_spare
    if [[ "$add_spare" =~ [Yy] ]]; then
        echo -e "\n可用磁盘列表:"
        get_available_disks
        
        read -p "输入备用设备 (如 sdx): " spare_device
        if [[ -n "$spare_device" ]]; then
            options+="--spare-devices=1 /dev/${spare_device} "
        fi
    fi
    
    # 阵列名称
    read -p "阵列名称 (默认: md0): " array_name
    if [[ -z "$array_name" ]]; then
        array_name="md0"
    fi
    
    echo "$options $array_name"
}

# 创建 RAID 阵列
create_raid() {
    local level=$1
    shift
    local devices=($@)
    local options=""
    local array_name="md0"
    
    # 提取选项和阵列名称
    for arg in "$@"; do
        if [[ "$arg" == --* ]]; then
            options+="$arg "
        elif [[ "$arg" == md* ]]; then
            array_name="$arg"
        fi
    done
    
    # 移除选项和阵列名称，保留设备列表
    devices=(${devices[@]//--*/})
    devices=(${devices[@]//md*/})
    
    log_info "创建 RAID ${level} 阵列 /dev/${array_name}"
    log_info "使用设备: ${devices[@]}"
    log_info "选项: ${options}"
    
    # 确认操作
    echo -e "\n${RED}警告: 此操作将清除所选磁盘上的所有数据!${NC}"
    read -p "确认创建 RAID 阵列? (输入 'YES' 确认): " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    # 创建 RAID
    mdadm --create --verbose "/dev/${array_name}" --level="${level}" --raid-devices="${#devices[@]}" ${options} ${devices[@]}
    
    # 等待阵列同步
    log_info "RAID 阵列正在同步，这可能需要一些时间..."
    watch -n 5 "cat /proc/mdstat"
}

# 验证 RAID 状态
verify_raid() {
    local array_name=$1
    
    log_info "验证 RAID 状态..."
    
    # 检查阵列是否存在
    if [[ ! -b "/dev/${array_name}" ]]; then
        log_error "RAID 阵列 /dev/${array_name} 不存在"
    fi
    
    # 显示阵列详细信息
    echo -e "\n${BLUE}RAID 阵列详细信息:${NC}"
    mdadm --detail "/dev/${array_name}"
    
    # 检查阵列状态
    local status=$(cat /proc/mdstat | grep "${array_name}" | awk '{print $3}')
    if [[ "$status" != "active" ]]; then
        log_warning "RAID 阵列状态异常: ${status}"
    else
        log_info "RAID 阵列状态正常"
    fi
}

# 保存配置
save_config() {
    local array_name=$1
    
    # 创建备份目录
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    # 备份当前配置
    local backup_file="${CONFIG_BACKUP_DIR}/mdadm_$(date +%Y%m%d_%H%M%S).conf"
    cp "$MDADM_CONF" "$backup_file" 2>/dev/null || true
    
    # 保存新配置
    log_info "保存 RAID 配置到 ${MDADM_CONF}"
    mdadm --detail --scan >> "$MDADM_CONF"
    
    # 更新 initramfs
    if command -v update-initramfs &> /dev/null; then
        update-initramfs -u
    elif command -v dracut &> /dev/null; then
        dracut -f
    fi
    
    log_info "配置已备份至: ${backup_file}"
}

# 创建文件系统
create_filesystem() {
    local array_name=$1
    
    echo -e "\n${BLUE}选择文件系统类型:${NC}"
    echo "1) ext4 (推荐)"
    echo "2) xfs (高性能)"
    echo "3) btrfs (高级功能)"
    echo "4) 跳过创建文件系统"
    
    read -p "输入选择 (1-4): " choice
    
    case $choice in
        1)
            log_info "创建 ext4 文件系统..."
            mkfs.ext4 "/dev/${array_name}"
            ;;
        2)
            log_info "创建 xfs 文件系统..."
            mkfs.xfs "/dev/${array_name}"
            ;;
        3)
            log_info "创建 btrfs 文件系统..."
            mkfs.btrfs "/dev/${array_name}"
            ;;
        4)
            log_info "跳过文件系统创建"
            return
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    # 询问是否挂载
    read -p "是否要挂载新创建的 RAID 阵列? (y/N): " mount_it
    if [[ "$mount_it" =~ [Yy] ]]; then
        read -p "输入挂载点 (如 /mnt/raid): " mount_point
        if [[ -n "$mount_point" ]]; then
            mkdir -p "$mount_point"
            mount "/dev/${array_name}" "$mount_point"
            echo "/dev/${array_name} $mount_point auto defaults 0 0" >> /etc/fstab
            log_info "RAID 阵列已挂载到 ${mount_point} 并添加到 fstab"
        fi
    fi
}

# 显示使用说明
show_usage() {
    echo -e "${BLUE}RAID 配置脚本使用说明:${NC}"
    echo "此脚本帮助配置软件 RAID 阵列"
    echo "支持 RAID 级别: 0, 1, 5, 6, 10"
    echo ""
    echo "注意事项:"
    echo "1. 此操作将清除所选磁盘上的所有数据!"
    echo "2. 请确保已备份重要数据!"
    echo "3. 建议在物理机或虚拟机上测试后再在生产环境使用"
    echo ""
    echo "使用方式:"
    echo "  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -l, --list     列出可用磁盘"
    echo "  -s, --status   显示当前 RAID 状态"
}

# 列出可用磁盘
list_disks() {
    echo -e "${BLUE}可用磁盘列表:${NC}"
    get_available_disks
    exit 0
}

# 显示 RAID 状态
show_status() {
    echo -e "${BLUE}当前 RAID 状态:${NC}"
    if [[ -f /proc/mdstat ]]; then
        cat /proc/mdstat
    else
        echo "未检测到 RAID 阵列"
    fi
    
    echo -e "\n${BLUE}详细 RAID 信息:${NC}"
    for array in /dev/md*; do
        if [[ -b "$array" ]]; then
            echo -e "\n阵列: $array"
            mdadm --detail "$array" | grep -E "State|Raid Level|Array Size|Active|Working|Failed"
        fi
    done
    exit 0
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--list)
                list_disks
                ;;
            -s|--status)
                show_status
                ;;
            *)
                echo "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    
    # 显示标题
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}          RAID 配置脚本          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # 检查环境
    check_root
    check_mdadm
    
    # 选择 RAID 级别
    local raid_level=$(select_raid_level)
    
    # 选择设备
    local devices=$(select_devices $raid_level)
    
    # 高级配置
    local advanced_options=$(configure_advanced)
    
    # 提取阵列名称
    local array_name=$(echo $advanced_options | grep -o "md[0-9]*" || echo "md0")
    local options=$(echo $advanced_options | sed "s/$array_name//")
    
    # 显示配置摘要
    echo -e "\n${BLUE}配置摘要:${NC}"
    echo "RAID 级别: $raid_level"
    echo "设备: $devices"
    echo "选项: $options"
    echo "阵列名称: $array_name"
    echo ""
    
    # 确认创建
    read -p "是否继续创建 RAID 阵列? (y/N): " confirm
    if [[ ! "$confirm" =~ [Yy] ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    # 创建 RAID
    create_raid $raid_level $devices $options $array_name
    
    # 验证 RAID
    verify_raid $array_name
    
    # 保存配置
    save_config $array_name
    
    # 创建文件系统
    create_filesystem $array_name
    
    log_info "RAID 配置完成! 阵列: /dev/${array_name}"
}

# 执行主函数
main "$@"
