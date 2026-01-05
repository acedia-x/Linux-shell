 #!/bin/bash
 
LOG_FILE="server_status.log"
 
# 记录日志函数
function log {
    echo "$1" | tee -a $LOG_FILE
}
 
# 从model name中提取额定CPU频率 (GHz)
function extract_max_freq {
    model_name_line=$(grep -m 1 'model name' /proc/cpuinfo)
    echo "$model_name_line" | grep -oP '\d+\.\d+(?=GHz)' | head -n 1
}
 
# 检测CPU信息
function get_cpu_info {
    log "CPU信息:"
    if [ -f /proc/cpuinfo ]; then
        model_name=$(grep -m 1 'model name' /proc/cpuinfo)
        cpu_cores=$(grep -m 1 'cpu cores' /proc/cpuinfo)
        siblings=$(grep -m 1 'siblings' /proc/cpuinfo)
        cpu_mhz=$(grep -m 1 'cpu MHz' /proc/cpuinfo | awk '{print $4 / 1000 " GHz"}')
        
        log "$model_name"
        log "$cpu_cores"
        log "$siblings"
        log "当前CPU频率: $cpu_mhz"
        
        # 获取额定CPU频率
        max_freq=$(extract_max_freq)
        if [ -n "$max_freq" ]; then
            log "额定CPU频率: $max_freq GHz"
        else
            log "无法提取额定CPU频率"
        fi
        
        # 检测虚拟化支持
        if grep -q 'vmx\|svm' /proc/cpuinfo; then
            log "虚拟化状态: 已启用"
        else
            log "虚拟化状态: 未启用"
        fi
    else
        log "无法获取CPU信息"
    fi
    log ""
}
 
# 检测CPU使用率
function get_cpu_usage {
    log "CPU使用率:"
    if [ -f /proc/cpuinfo ]; then
        current_freq=$(grep 'cpu MHz' /proc/cpuinfo | awk '{sum += $4} END {print sum / NR / 1000}') # 转换为GHz
        max_freq=$(extract_max_freq)
        if [ -n "$max_freq" ]; then
            cpu_usage=$(awk "BEGIN {printf \"%.2f\", ($current_freq / $max_freq) * 100}")
            log "$cpu_usage%"
        else
            log "无法计算CPU使用率，因为无法提取额定CPU频率"
        fi
    else
        log "无法获取CPU使用率"
    fi
    log ""
}
 
# 检测内存信息
function get_memory_info {
    log "内存信息:"
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1024 / 1024 " GB"}')
        mem_free=$(grep MemFree /proc/meminfo | awk '{print $2 / 1024 / 1024 " GB"}')
        mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2 / 1024 / 1024 " GB"}')
        buffers=$(grep Buffers /proc/meminfo | awk '{print $2 / 1024 / 1024 " GB"}')
        cached=$(grep ^Cached /proc/meminfo | awk '{print $2 / 1024 / 1024 " GB"}')
        log "总内存: $mem_total"
        log "空闲内存: $mem_free"
        log "可用内存: $mem_available"
        log "缓冲区: $buffers"
        log "缓存: $cached"
    else
        log "无法获取内存信息"
    fi
    log ""
}
 
# 检测内存使用率
function get_memory_usage {
    log "内存使用率:"
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_usage=$(awk "BEGIN {printf \"%.2f\", (($mem_total - $mem_available) / $mem_total) * 100}")
        log "$mem_usage%"
    else
        log "无法获取内存使用率"
    fi
    log ""
}
 
# 检测磁盘使用情况
function get_disk_info {
    log "磁盘使用情况:"
    log "$(df -h)"
    log ""
}
 
# 检测硬盘使用率
function get_disk_usage {
    log "硬盘使用率:"
    log "$(df -h | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $1 " " $5 }')"
    log ""
}
 
# 检测网络信息
function get_network_info {
    log "网络信息:"
    log "$(ip -br a)"
    log ""
}
 
# 检测网络流量
function get_network_traffic {
    log "网络流量:"
    for iface in $(ls /sys/class/net/ | grep -vE 'lo|bonding_masters'); do
        if [ -d /sys/class/net/$iface/statistics ]; then
            rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes)
            tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes)
            log "$iface 接收: $((rx_bytes / 1024)) KB 发送: $((tx_bytes / 1024)) KB"
        fi
    done
    log ""
}
 
# 检测当前系统负载
function get_system_load {
    log "系统负载:"
    if [ -f /proc/loadavg ]; then
        log "$(cat /proc/loadavg)"
    else
        log "无法获取系统负载"
    fi
    log ""
}
 
# 主程序
function main {
    echo "服务器硬件配置及资源使用情况检测脚本" | tee $LOG_FILE
    echo "--------------------------------------" | tee -a $LOG_FILE
    get_cpu_info
    get_cpu_usage
    get_memory_info
    get_memory_usage
    get_disk_info
    get_disk_usage
    get_network_info
    get_network_traffic
    get_system_load
}
 
# 执行主程序
main
