#!/bin/bash
# 脚本名: proxy-toggle_v2.sh
# 描述: 代理开关脚本，修复测试逻辑

# 代理配置
PROXY_IP="192.168.66.1"
HTTP_PORT="7890"
SOCKS_PORT="7891"
NO_PROXY="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函数：显示用法
usage() {
    echo "使用方法: source $0 {on|off|status|test|check}"
    echo "  on      - 启用代理"
    echo "  off     - 禁用代理"
    echo "  status  - 查看当前代理状态"
    echo "  test    - 测试代理连接"
    echo "  check   - 检查代理服务器状态"
}

# 函数：检查端口是否开放
check_port() {
    local ip=$1
    local port=$2
    timeout 2 bash -c ">/dev/tcp/$ip/$port" 2>/dev/null
    return $?
}

# 函数：测试HTTP代理
test_http_proxy() {
    local proxy_url="http://${PROXY_IP}:${HTTP_PORT}"
    echo -e "${BLUE}测试 HTTP 代理...${NC}"
    
    # 使用curl测试HTTP代理，使用HTTPS网址避免重定向问题
    local result
    result=$(timeout 10 curl -s -x "$proxy_url" -I https://www.github.com 2>&1)
    
    # 检查是否成功连接到代理服务器（任何HTTP响应都表示代理工作）
    if echo "$result" | grep -q "HTTP/"; then
        echo -e "${GREEN}HTTP 代理测试: 成功 ✓${NC}"
        echo "响应: $(echo "$result" | head -1)"
        return 0
    elif echo "$result" | grep -q "Failed to connect"; then
        echo -e "${RED}HTTP 代理测试: 失败 ✗ - 无法连接到代理服务器${NC}"
        return 1
    else
        echo -e "${RED}HTTP 代理测试: 失败 ✗${NC}"
        echo "错误信息: $result"
        return 1
    fi
}

# 函数：测试SOCKS5代理
test_socks5_proxy() {
    echo -e "${BLUE}测试 SOCKS5 代理...${NC}"
    
    # 使用curl测试SOCKS5代理
    local result
    result=$(timeout 10 curl -s --socks5 "${PROXY_IP}:${SOCKS_PORT}" -I https://www.github.com 2>&1)
    
    # 检查是否成功连接到代理服务器
    if echo "$result" | grep -q "HTTP/"; then
        echo -e "${GREEN}SOCKS5 代理测试: 成功 ✓${NC}"
        echo "响应: $(echo "$result" | head -1)"
        return 0
    elif echo "$result" | grep -q "Failed to connect"; then
        echo -e "${RED}SOCKS5 代理测试: 失败 ✗ - 无法连接到SOCKS5代理${NC}"
        return 1
    else
        echo -e "${RED}SOCKS5 代理测试: 失败 ✗${NC}"
        echo "错误信息: $result"
        return 1
    fi
}

# 函数：检查代理服务器状态
check_proxy_server() {
    echo -e "${BLUE}=== 代理服务器状态检查 ===${NC}"
    
    echo -e "${YELLOW}检查端口连通性...${NC}"
    if check_port "$PROXY_IP" "$HTTP_PORT"; then
        echo -e "${GREEN}HTTP 端口 ${HTTP_PORT}: 开放 ✓${NC}"
    else
        echo -e "${RED}HTTP 端口 ${HTTP_PORT}: 关闭 ✗${NC}"
    fi
    
    if check_port "$PROXY_IP" "$SOCKS_PORT"; then
        echo -e "${GREEN}SOCKS5 端口 ${SOCKS_PORT}: 开放 ✓${NC}"
    else
        echo -e "${RED}SOCKS5 端口 ${SOCKS_PORT}: 关闭 ✗${NC}"
    fi
    
    # 检查代理服务器进程
    echo -e "${YELLOW}检查代理服务...${NC}"
    if ping -c 1 -W 1 "$PROXY_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}代理服务器可达 ✓${NC}"
    else
        echo -e "${RED}代理服务器不可达 ✗${NC}"
    fi
}

# 函数：测试代理连接
test_proxy_connection() {
    echo -e "${BLUE}=== 代理连接测试 ===${NC}"
    
    check_proxy_server
    echo
    
    test_http_proxy
    echo
    
    test_socks5_proxy
    echo
    
    # 测试直接连接
    echo -e "${BLUE}测试直接连接...${NC}"
    if timeout 10 curl -s -I https://www.github.com >/dev/null 2>&1; then
        echo -e "${GREEN}直接连接: 正常 ✓${NC}"
    else
        echo -e "${RED}直接连接: 失败 ✗${NC}"
    fi
}

# 函数：启用代理
enable_proxy() {
    # 设置环境变量
    export http_proxy="http://${PROXY_IP}:${HTTP_PORT}"
    export https_proxy="http://${PROXY_IP}:${HTTP_PORT}"
    export HTTP_PROXY="http://${PROXY_IP}:${HTTP_PORT}"
    export HTTPS_PROXY="http://${PROXY_IP}:${HTTP_PORT}"
    export all_proxy="socks5://${PROXY_IP}:${SOCKS_PORT}"
    export ALL_PROXY="socks5://${PROXY_IP}:${SOCKS_PORT}"
    export no_proxy="$NO_PROXY"
    export NO_PROXY="$NO_PROXY"
    
    # 设置git代理
    git config --global http.proxy "http://${PROXY_IP}:${HTTP_PORT}"
    git config --global https.proxy "http://${PROXY_IP}:${HTTP_PORT}"
    
    echo -e "${GREEN}代理已启用 ✓${NC}"
    echo -e "${GREEN}HTTP 代理: http://${PROXY_IP}:${HTTP_PORT}${NC}"
    echo -e "${GREEN}SOCKS5 代理: socks5://${PROXY_IP}:${SOCKS_PORT}${NC}"
    
    # 测试连接
    echo -e "${YELLOW}正在测试代理连接性...${NC}"
    if test_http_proxy; then
        echo -e "${GREEN}代理设置成功！${NC}"
    else
        echo -e "${YELLOW}警告: 代理已设置但连接测试失败${NC}"
        echo -e "${YELLOW}请运行 'source $0 test' 查看详细错误${NC}"
    fi
}

# 函数：禁用代理
disable_proxy() {
    # 清除环境变量
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset all_proxy
    unset ALL_PROXY
    unset no_proxy
    unset NO_PROXY
    
    # 清除git代理
    git config --global --unset http.proxy
    git config --global --unset https.proxy
    
    echo -e "${GREEN}代理已禁用 ✓${NC}"
    
    # 测试直接连接
    echo -e "${YELLOW}测试直接连接...${NC}"
    if timeout 10 curl -s -I https://www.github.com >/dev/null 2>&1; then
        echo -e "${GREEN}直接连接正常 ✓${NC}"
    else
        echo -e "${RED}直接连接失败 ✗${NC}"
    fi
}

# 函数：显示代理状态
show_proxy_status() {
    echo -e "${BLUE}=== 当前代理状态 ===${NC}"
    
    if [ -n "$http_proxy" ]; then
        echo -e "${GREEN}代理已启用 ✓${NC}"
        echo "HTTP 代理: $http_proxy"
        echo "HTTPS 代理: $https_proxy"
        echo "SOCKS5 代理: $all_proxy"
        echo "排除地址: $no_proxy"
    else
        echo -e "${YELLOW}代理未设置${NC}"
    fi
    
    echo -e "${YELLOW}Git 代理设置:${NC}"
    git config --global --get http.proxy || echo "未设置"
    git config --global --get https.proxy || echo "未设置"
}

# 主程序
main() {
    case "$1" in
        on|enable)
            enable_proxy
            ;;
        off|disable)
            disable_proxy
            ;;
        status)
            show_proxy_status
            ;;
        test)
            test_proxy_connection
            ;;
        check)
            check_proxy_server
            ;;
        *)
            usage
            ;;
    esac
}

# 如果直接执行脚本，显示用法
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo -e "${RED}错误: 请使用 'source $0' 而不是直接执行${NC}"
    echo -e "${YELLOW}这样设置的环境变量才能在当前shell中生效${NC}"
    usage
    exit 1
fi

# 执行主函数
main "$@"
