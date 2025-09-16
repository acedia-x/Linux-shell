#!/bin/bash

LOGFILE="/var/log/redis_report.log"
TIME=$(date '+%Y-%m-%d %H:%M:%S')

INSTANCES=$(ps -ef | grep redis-server | grep -v grep | awk '{print $9}')

for instance in $INSTANCES; do
    HOST=$(echo $instance | awk -F: '{print $1}')
    PORT=$(echo $instance | awk -F: '{print $2}')

    if [[ -z "$PORT" ]]; then
        PORT=$HOST
        HOST="127.0.0.1"
    fi

    INFO=$(redis-cli -h "$HOST" -p "$PORT" info 2>/dev/null)
    if [[ -z "$INFO" ]]; then
        continue
    fi

    VERSION=$(echo "$INFO" | grep "^redis_version:" | cut -d: -f2)
    CPU=$(ps -aux | grep "redis-server.*:$PORT" | grep -v grep | awk '{print $3"%"}')
    MEMORY=$(echo "$INFO" | grep "^used_memory_human:" | cut -d: -f2)
    CLIENTS=$(echo "$INFO" | grep "^connected_clients:" | cut -d: -f2)
    LASTSAVE=$(echo "$INFO" | grep "^rdb_last_save_time:" | cut -d: -f2)
    INPUT=$(echo "$INFO" | grep "^total_net_input_bytes:" | cut -d: -f2)
    OUTPUT=$(echo "$INFO" | grep "^total_net_output_bytes:" | cut -d: -f2)
    REJECTED=$(echo "$INFO" | grep "^rejected_connections:" | cut -d: -f2)

    INPUT=$(echo "$INPUT" | tr -cd '0-9'); INPUT=${INPUT:-0}
    OUTPUT=$(echo "$OUTPUT" | tr -cd '0-9'); OUTPUT=${OUTPUT:-0}
    LASTSAVE=$(echo "$LASTSAVE" | tr -cd '0-9'); LASTSAVE=${LASTSAVE:-0}
    REJECTED=$(echo "$REJECTED" | tr -cd '0-9'); REJECTED=${REJECTED:-0}

    INPUT_KB=$((INPUT/1024))
    OUTPUT_KB=$((OUTPUT/1024))
    LASTSAVE_FMT=$(date -d @"$LASTSAVE" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)

    # 默认
    DEPLOY_TYPE="Unknown"
    REDIS_STATUS=0
    SLAVE_COUNT=0
    MASTER_HOST="N/A"

    # 哨兵判断
    MODE=$(echo "$INFO" | grep "^redis_mode:" | cut -d: -f2)
    if [[ "$MODE" == "sentinel" ]]; then
        DEPLOY_TYPE="Sentinel"
        REDIS_STATUS=2
    else
        # 集群判断
        CLUSTER_INFO=$(redis-cli -h "$HOST" -p "$PORT" cluster info 2>/dev/null)
        if [[ "$CLUSTER_INFO" =~ "cluster_state:ok" ]]; then
            NODES=$(redis-cli -h "$HOST" -p "$PORT" cluster nodes 2>/dev/null)
            ROLE_LINE=$(echo "$NODES" | grep "$HOST:$PORT")
            if [[ "$ROLE_LINE" =~ master ]]; then
                DEPLOY_TYPE="Master Cluster"
                REDIS_STATUS=0
            elif [[ "$ROLE_LINE" =~ slave ]]; then
                DEPLOY_TYPE="Slave Cluster"
                REDIS_STATUS=1
            else
                DEPLOY_TYPE="Cluster Unknown"
            fi
        else
            # 单节点主从判断
            ROLE=$(echo "$INFO" | grep "^role:" | cut -d: -f2)
            ROLE=${ROLE:-Unknown}
            if [[ "$ROLE" == "master" ]]; then
                SLAVE_COUNT=$(echo "$INFO" | grep "^connected_slaves:" | cut -d: -f2)
                SLAVE_COUNT=${SLAVE_COUNT:-0}
                DEPLOY_TYPE="Master"
                REDIS_STATUS=0
            elif [[ "$ROLE" == "slave" ]]; then
                MASTER_HOST=$(echo "$INFO" | grep "^master_host:" | cut -d: -f2)
                MASTER_HOST=${MASTER_HOST:-N/A}
                DEPLOY_TYPE="Slave"
                REDIS_STATUS=1
            fi
        fi
    fi

    # 输出日志+终端
    {
        echo "=============================="
        echo "时间: $TIME"
        echo "实例: $HOST:$PORT"
        echo "版本: ${VERSION:-N/A}"
        echo "部署类型: ${DEPLOY_TYPE:-Unknown}"
        [[ "$DEPLOY_TYPE" == "Master" ]] && echo "从节点数量: $SLAVE_COUNT"
        [[ "$DEPLOY_TYPE" == "Slave" ]] && echo "主节点IP: $MASTER_HOST"
        echo "CPU使用率: ${CPU:-N/A}"
        echo "内存使用: ${MEMORY:-N/A}"
        echo "当前连接数: ${CLIENTS:-N/A}"
        echo "最近一次持久存储: ${LASTSAVE_FMT:-N/A}"
        echo "网络流量: 输入 ${INPUT_KB}KB 输出 ${OUTPUT_KB}KB"
        echo "拒绝的连接数: $REJECTED"
        echo "Redis状态: $REDIS_STATUS"
    } | tee -a "$LOGFILE"
done

