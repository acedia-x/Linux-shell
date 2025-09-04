#!/bin/bash


# 清理输入，移除可能的退格字符和其他控制字符

# 检查服务名称是否为空
if [ -z "$1" ]; then
    echo "错误：服务名称不能为空"
    exit 1
fi

# 检查服务是否正在运行（同时检查systemctl和进程）
is_running=false
pid=""

# 首先尝试通过systemctl检查
if systemctl is-active --quiet "$1" 2>/dev/null; then
    is_running=true
    # 获取PID
    pid=$(systemctl show -p MainPID "$1" | cut -d= -f2)
    # 如果PID为0，则尝试通过ps命令查找
    if [ "$pid" -eq 0 ]; then
        pid=$(pgrep -f "$1" | head -n 1)
    fi
else
    # 如果没有systemctl服务，直接通过进程名查找
    pid=$(pgrep -f "$1" | head -n 1)
    if [ -n "$pid" ]; then
        is_running=true
    fi
fi

if [ "$is_running" = true ]; then
    # 获取端口信息
    port=$(ss -tlnp | awk -v pid="$pid" 'match($0, "pid="pid) {print $4}' | cut -d: -f2 | head -n1)
    
    # 如果未找到端口，尝试其他方法
    if [ -z "$port" ]; then
        # 对于Nginx等特殊服务，尝试检查配置文件中的端口
        if [ "$1" = "nginx" ]; then
            # 尝试查找Nginx配置文件中的监听端口
            nginx_conf=$(ps -o cmd= -p "$pid" | grep -o "\-c [^ ]*" | cut -d' ' -f2)
            if [ -z "$nginx_conf" ]; then
                nginx_conf="/usr/local/nginx/conf/nginx.conf"
            fi
            if [ -f "$nginx_conf" ]; then
                port=$(grep -E "^\s*listen" "$nginx_conf" | head -n 1 | grep -o "[0-9]*" | head -n 1)
            fi
        fi
    fi
    
    # 如果仍未找到端口，使用默认值
    if [ -z "$port" ]; then
        port="未找到"
    fi

    # 获取启动时间
    if [ -n "$pid" ] && [ "$pid" -ne 0 ]; then
        start_time=$(ps -o lstart= -p "$pid" 2>/dev/null)
        if [ -n "$start_time" ]; then
            echo "服务名称：$1, PID: $pid, 端口：$port, 启动时间：$start_time"
        else
            echo "服务名称：$1, PID: $pid, 端口：$port, 启动时间：未知"
        fi
    else
        echo "服务名称：$1 正在运行，但无法获取PID"
    fi
else
    echo "服务名称：$1 不在运行"
fi
