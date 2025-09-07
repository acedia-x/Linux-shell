#!/bin/bash

HOST_IP="192.168.66.1"

case "$1" in
    on)
        export http_proxy="http://$HOST_IP:7890"
        export https_proxy="http://$HOST_IP:7890"
        export HTTP_PROXY="http://$HOST_IP:7890"
        export HTTPS_PROXY="http://$HOST_IP:7890"
        echo "代理已启用"
        echo "HTTP 代理: http://$HOST_IP:7890"
        ;;
    off)
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        echo "代理已禁用"
        ;;
    status)
        echo "当前代理设置："
        env | grep -i proxy
        ;;
    test)
        echo "=== 代理连接测试 ==="
        
        # 测试端口连通性
        echo "测试端口连通性..."
        timeout 2 bash -c "echo > /dev/tcp/$HOST_IP/7890" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "端口 7890: 开放"
        else
            echo "端口 7890: 关闭或无法访问"
        fi
        
        timeout 2 bash -c "echo > /dev/tcp/$HOST_IP/7891" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "端口 7891: 开放"
        else
            echo "端口 7891: 关闭或无法访问"
        fi
        
        # 测试 HTTP 代理
        echo "测试 HTTP 代理..."
        result=$(timeout 10 curl -s -x http://$HOST_IP:7890 http://www.example.com 2>&1)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            echo "HTTP 代理测试: 成功"
        else
            echo "HTTP 代理测试: 失败 - $result"
        fi
        
        # 测试 SOCKS5 代理
        echo "测试 SOCKS5 代理..."
        result=$(timeout 10 curl -s --socks5 $HOST_IP:7891 http://www.example.com 2>&1)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            echo "SOCKS5 代理测试: 成功"
        else
            echo "SOCKS5 代理测试: 失败 - $result"
        fi
        ;;
    *)
        echo "使用方法: source proxy-toggle.sh {on|off|status|test}"
        ;;
esac
